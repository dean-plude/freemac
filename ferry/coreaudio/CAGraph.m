/* SPDX-License-Identifier: GPL-3.0-or-later
 *
 * Audio unit graphs (freemac 1.NEXT), written from Apple's public
 * documentation of AUGraph.h.
 *
 * A graph holds nodes, each an audio component that the graph opens as an
 * audio unit (AUGraphOpen), and the interactions between them: one node's
 * output connected to another's input, or a program's render callback on a
 * node's input. The graph's head is its output unit; starting the graph
 * starts it, and it pulls each node in turn through the connections. A
 * generic output head renders only when the program pulls on it with
 * AudioUnitRender, as VLC's MIDI decoder does (CAMusicDevice.m).
 *
 * Each connection is made by giving the destination unit a render callback
 * that renders the source unit, so it works for Ferry's own output units
 * and for plug-in units alike. When the graph initializes, each
 * destination's input takes its source's output format, and every node
 * takes the head's largest slice. Changes made while the graph is
 * initialized take effect at once, so AUGraphUpdate has nothing left to do.
 */
#import "CAInternal.h"
#include <stdlib.h>
#include <string.h>

typedef struct interaction {
    struct interaction *next;
    UInt32 type; /* kAUNodeInteraction_Connection or _InputCallback */
    AUNode src, dst;
    UInt32 src_bus, dst_bus;
    AURenderCallbackStruct callback;
    struct OpaqueAUGraph *graph;
    AudioUnit src_unit; /* while the graph is open */
} interaction;

typedef struct node {
    struct node *next;
    AUNode id;
    AudioComponentDescription desc;
    AudioUnit unit; /* while the graph is open */
} node;

typedef struct graph_notify {
    struct graph_notify *next;
    AURenderCallback proc;
    void *ref;
} graph_notify;

struct OpaqueAUGraph {
    pthread_mutex_t lock;
    node *nodes;
    interaction *interactions;
    graph_notify *notifies;
    AUNode next_id;
    int open, initialized, running;
};

static node *find_node(AUGraph g, AUNode id)
{
    for (node *n = g->nodes; n; n = n->next)
        if (n->id == id)
            return n;
    return NULL;
}

static node *head_node(AUGraph g)
{
    for (node *n = g->nodes; n; n = n->next)
        if (n->desc.componentType == kAudioUnitType_Output)
            return n;
    return NULL;
}

/* a connection's render callback: renders the source node into the destination's buffers */
static OSStatus render_source(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *t, UInt32 bus,
                              UInt32 frames, AudioBufferList *io)
{
    interaction *i = ref;
    (void)bus;
    if (!i->src_unit)
        return kAudioUnitErr_NoConnection;
    return AudioUnitRender(i->src_unit, flags, t, i->src_bus, frames, io);
}

/* gives a destination node's unit its input, from the interaction */
static OSStatus apply(AUGraph g, interaction *i)
{
    node *dst = find_node(g, i->dst);
    if (!dst || !dst->unit)
        return noErr; /* made when the graph opens */
    AURenderCallbackStruct cb = i->callback;
    if (i->type == kAUNodeInteraction_Connection) {
        node *src = find_node(g, i->src);
        i->src_unit = src ? src->unit : NULL;
        cb.inputProc = render_source;
        cb.inputProcRefCon = i;
    }
    return AudioUnitSetProperty(dst->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, i->dst_bus,
                                &cb, sizeof cb);
}

static void unapply(AUGraph g, interaction *i)
{
    node *dst = find_node(g, i->dst);
    if (dst && dst->unit) {
        AURenderCallbackStruct none = {NULL, NULL};
        AudioUnitSetProperty(dst->unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, i->dst_bus,
                             &none, sizeof none);
    }
    i->src_unit = NULL;
}

/* takes away whatever feeds a node's input */
static void remove_input(AUGraph g, AUNode dst, UInt32 bus)
{
    for (interaction **i = &g->interactions; *i;) {
        if ((*i)->dst == dst && (*i)->dst_bus == bus) {
            interaction *gone = *i;
            *i = gone->next;
            unapply(g, gone);
            free(gone);
        } else
            i = &(*i)->next;
    }
}

static OSStatus add_interaction(AUGraph g, interaction *i)
{
    remove_input(g, i->dst, i->dst_bus);
    i->graph = g;
    interaction **end = &g->interactions;
    while (*end)
        end = &(*end)->next;
    *end = i;
    return g->open ? apply(g, i) : noErr;
}

/* ---- the graph ---------------------------------------------------------------------------- */

OSStatus NewAUGraph(AUGraph *out)
{
    if (!out)
        return kAudio_ParamError;
    AUGraph g = calloc(1, sizeof *g);
    if (!g)
        return kAudio_MemFullError;
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&g->lock, &attr);
    pthread_mutexattr_destroy(&attr);
    g->next_id = 1;
    *out = g;
    return noErr;
}

OSStatus DisposeAUGraph(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    AUGraphStop(g);
    AUGraphUninitialize(g);
    AUGraphClose(g);
    while (g->interactions) {
        interaction *i = g->interactions;
        g->interactions = i->next;
        free(i);
    }
    while (g->nodes) {
        node *n = g->nodes;
        g->nodes = n->next;
        free(n);
    }
    while (g->notifies) {
        graph_notify *n = g->notifies;
        g->notifies = n->next;
        free(n);
    }
    pthread_mutex_destroy(&g->lock);
    free(g);
    return noErr;
}

/* ---- nodes ---- */

static OSStatus open_node(node *n)
{
    AudioComponent c = AudioComponentFindNext(NULL, &n->desc);
    if (!c)
        return kAUGraphErr_InvalidAudioUnit; /* no component fits the node's description */
    return AudioComponentInstanceNew(c, &n->unit);
}

OSStatus AUGraphAddNode(AUGraph g, const AudioComponentDescription *desc, AUNode *out)
{
    if (!g || !desc || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    if (desc->componentType == kAudioUnitType_Output && head_node(g)) {
        pthread_mutex_unlock(&g->lock);
        return kAUGraphErr_OutputNodeErr; /* a graph has one output unit */
    }
    node *n = calloc(1, sizeof *n);
    if (!n) {
        pthread_mutex_unlock(&g->lock);
        return kAudio_MemFullError;
    }
    n->id = g->next_id++;
    n->desc = *desc;
    OSStatus err = g->open ? open_node(n) : noErr;
    if (err) {
        free(n);
        pthread_mutex_unlock(&g->lock);
        return err;
    }
    node **end = &g->nodes;
    while (*end)
        end = &(*end)->next;
    *end = n;
    if (g->initialized && n->unit)
        AudioUnitInitialize(n->unit);
    *out = n->id;
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphRemoveNode(AUGraph g, AUNode id)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *n = find_node(g, id);
    if (!n) {
        pthread_mutex_unlock(&g->lock);
        return kAUGraphErr_NodeNotFound;
    }
    for (interaction **i = &g->interactions; *i;) {
        if ((*i)->dst == id || ((*i)->type == kAUNodeInteraction_Connection && (*i)->src == id)) {
            interaction *gone = *i;
            *i = gone->next;
            unapply(g, gone);
            free(gone);
        } else
            i = &(*i)->next;
    }
    for (node **p = &g->nodes; *p; p = &(*p)->next)
        if (*p == n) {
            *p = n->next;
            break;
        }
    if (n->unit) {
        if (g->running && n->desc.componentType == kAudioUnitType_Output)
            AudioOutputUnitStop(n->unit);
        AudioComponentInstanceDispose(n->unit);
    }
    free(n);
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphGetNodeCount(AUGraph g, UInt32 *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    UInt32 count = 0;
    for (node *n = g->nodes; n; n = n->next)
        count++;
    *out = count;
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphGetIndNode(AUGraph g, UInt32 index, AUNode *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *n = g->nodes;
    for (UInt32 i = 0; n && i < index; i++)
        n = n->next;
    if (n)
        *out = n->id;
    pthread_mutex_unlock(&g->lock);
    return n ? noErr : kAudio_ParamError;
}

OSStatus AUGraphNodeInfo(AUGraph g, AUNode id, AudioComponentDescription *desc, AudioUnit *unit)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *n = find_node(g, id);
    if (n) {
        if (desc)
            *desc = n->desc;
        if (unit)
            *unit = n->unit;
    }
    pthread_mutex_unlock(&g->lock);
    return n ? noErr : kAUGraphErr_NodeNotFound;
}

/* ---- interactions ---- */

OSStatus AUGraphConnectNodeInput(AUGraph g, AUNode src, UInt32 src_bus, AUNode dst, UInt32 dst_bus)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = noErr;
    if (!find_node(g, src) || !find_node(g, dst))
        err = kAUGraphErr_NodeNotFound;
    else if (src == dst)
        err = kAUGraphErr_InvalidConnection;
    else {
        interaction *i = calloc(1, sizeof *i);
        if (!i)
            err = kAudio_MemFullError;
        else {
            i->type = kAUNodeInteraction_Connection;
            i->src = src, i->src_bus = src_bus, i->dst = dst, i->dst_bus = dst_bus;
            err = add_interaction(g, i);
        }
    }
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphSetNodeInputCallback(AUGraph g, AUNode dst, UInt32 dst_bus, const AURenderCallbackStruct *cb)
{
    if (!g || !cb)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = noErr;
    if (!find_node(g, dst))
        err = kAUGraphErr_NodeNotFound;
    else {
        interaction *i = calloc(1, sizeof *i);
        if (!i)
            err = kAudio_MemFullError;
        else {
            i->type = kAUNodeInteraction_InputCallback;
            i->dst = dst, i->dst_bus = dst_bus, i->callback = *cb;
            err = add_interaction(g, i);
        }
    }
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphDisconnectNodeInput(AUGraph g, AUNode dst, UInt32 dst_bus)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = find_node(g, dst) ? noErr : kAUGraphErr_NodeNotFound;
    if (!err)
        remove_input(g, dst, dst_bus);
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphClearConnections(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    while (g->interactions) {
        interaction *i = g->interactions;
        g->interactions = i->next;
        unapply(g, i);
        free(i);
    }
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

static void describe(const interaction *i, AUNodeInteraction *out)
{
    memset(out, 0, sizeof *out);
    out->nodeInteractionType = i->type;
    if (i->type == kAUNodeInteraction_Connection)
        out->nodeInteraction.connection = (AUNodeConnection){i->src, i->src_bus, i->dst, i->dst_bus};
    else
        out->nodeInteraction.inputCallback = (AUNodeRenderCallback){i->dst, i->dst_bus, i->callback};
}

OSStatus AUGraphGetNumberOfInteractions(AUGraph g, UInt32 *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    UInt32 count = 0;
    for (interaction *i = g->interactions; i; i = i->next)
        count++;
    *out = count;
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphGetInteractionInfo(AUGraph g, UInt32 index, AUNodeInteraction *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    interaction *i = g->interactions;
    for (UInt32 k = 0; i && k < index; k++)
        i = i->next;
    if (i)
        describe(i, out);
    pthread_mutex_unlock(&g->lock);
    return i ? noErr : kAudio_ParamError;
}

static int involves(const interaction *i, AUNode id)
{
    return i->dst == id || (i->type == kAUNodeInteraction_Connection && i->src == id);
}

OSStatus AUGraphCountNodeInteractions(AUGraph g, AUNode id, UInt32 *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = find_node(g, id) ? noErr : kAUGraphErr_NodeNotFound;
    UInt32 count = 0;
    for (interaction *i = g->interactions; i; i = i->next)
        count += involves(i, id);
    *out = count;
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphGetNodeInteractions(AUGraph g, AUNode id, UInt32 *io_count, AUNodeInteraction *out)
{
    if (!g || !io_count || !out)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = find_node(g, id) ? noErr : kAUGraphErr_NodeNotFound;
    UInt32 n = 0;
    for (interaction *i = g->interactions; i && n < *io_count; i = i->next)
        if (involves(i, id))
            describe(i, &out[n++]);
    *io_count = n;
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphUpdate(AUGraph g, Boolean *updated)
{
    if (!g)
        return kAudio_ParamError;
    if (updated)
        *updated = 1; /* every change has already taken effect */
    return noErr;
}

/* ---- opening, initializing and running ---- */

OSStatus AUGraphOpen(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = noErr;
    if (!g->open) {
        for (node *n = g->nodes; n && !err; n = n->next)
            if (!n->unit)
                err = open_node(n);
        if (err) {
            for (node *n = g->nodes; n; n = n->next)
                if (n->unit) {
                    AudioComponentInstanceDispose(n->unit);
                    n->unit = NULL;
                }
        } else {
            g->open = 1;
            for (interaction *i = g->interactions; i; i = i->next)
                apply(g, i);
            node *head = head_node(g);
            for (graph_notify *r = g->notifies; r && head; r = r->next)
                AudioUnitAddRenderNotify(head->unit, r->proc, r->ref);
        }
    }
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphClose(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    if (g->open) {
        AUGraphStop(g);
        AUGraphUninitialize(g);
        for (interaction *i = g->interactions; i; i = i->next)
            i->src_unit = NULL;
        for (node *n = g->nodes; n; n = n->next)
            if (n->unit) {
                AudioComponentInstanceDispose(n->unit);
                n->unit = NULL;
            }
        g->open = 0;
    }
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

/* each destination takes its source's output format, and every node the head's slice */
static void propagate(AUGraph g)
{
    node *head = head_node(g);
    UInt32 max_frames = 0, size = sizeof max_frames;
    if (head && head->unit &&
        AudioUnitGetProperty(head->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                             &max_frames, &size))
        max_frames = 0;
    for (node *n = g->nodes; n && max_frames; n = n->next)
        if (n != head && n->unit)
            AudioUnitSetProperty(n->unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0,
                                 &max_frames, sizeof max_frames);
    /* in the order the sound flows: a destination's format may be another connection's source */
    UInt32 count = 0;
    for (interaction *i = g->interactions; i; i = i->next)
        count++;
    for (UInt32 pass = 0; pass < count; pass++)
        for (interaction *i = g->interactions; i; i = i->next) {
            if (i->type != kAUNodeInteraction_Connection)
                continue;
            node *src = find_node(g, i->src), *dst = find_node(g, i->dst);
            if (!src || !dst || !src->unit || !dst->unit)
                continue;
            AudioStreamBasicDescription f, have;
            UInt32 fs = sizeof f, hs = sizeof have;
            if (AudioUnitGetProperty(src->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, i->src_bus,
                                     &f, &fs))
                continue;
            if (!AudioUnitGetProperty(dst->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i->dst_bus,
                                      &have, &hs) &&
                !memcmp(&f, &have, sizeof f))
                continue;
            AudioUnitSetProperty(dst->unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, i->dst_bus, &f,
                                 sizeof f);
        }
}

OSStatus AUGraphInitialize(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = noErr;
    if (!g->open)
        err = kAUGraphErr_CannotDoInCurrentContext;
    else if (!g->initialized) {
        propagate(g);
        for (node *n = g->nodes; n && !err; n = n->next)
            if (n->unit)
                err = AudioUnitInitialize(n->unit);
        if (err) {
            for (node *n = g->nodes; n; n = n->next)
                if (n->unit)
                    AudioUnitUninitialize(n->unit);
        } else
            g->initialized = 1;
    }
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphUninitialize(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    if (g->initialized) {
        AUGraphStop(g);
        for (node *n = g->nodes; n; n = n->next)
            if (n->unit)
                AudioUnitUninitialize(n->unit);
        g->initialized = 0;
    }
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphStart(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    OSStatus err = noErr;
    node *head = head_node(g);
    if (!g->open)
        err = kAUGraphErr_CannotDoInCurrentContext;
    else if (!head)
        err = kAUGraphErr_OutputNodeErr;
    else if (!g->running) {
        if (!g->initialized)
            err = AUGraphInitialize(g);
        if (!err)
            err = AudioOutputUnitStart(head->unit);
        if (!err)
            g->running = 1;
    }
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphStop(AUGraph g)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    node *head = head_node(g);
    if (g->running && head && head->unit)
        AudioOutputUnitStop(head->unit);
    g->running = 0;
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

OSStatus AUGraphIsOpen(AUGraph g, Boolean *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    *out = g->open != 0;
    return noErr;
}

OSStatus AUGraphIsInitialized(AUGraph g, Boolean *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    *out = g->initialized != 0;
    return noErr;
}

OSStatus AUGraphIsRunning(AUGraph g, Boolean *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    *out = g->running != 0;
    return noErr;
}

OSStatus AUGraphGetCPULoad(AUGraph g, Float32 *out)
{
    if (!g || !out)
        return kAudio_ParamError;
    *out = 0; /* not measured */
    return noErr;
}

OSStatus AUGraphGetMaxCPULoad(AUGraph g, Float32 *out)
{
    return AUGraphGetCPULoad(g, out);
}

OSStatus AUGraphAddRenderNotify(AUGraph g, AURenderCallback proc, void *ref)
{
    if (!g || !proc)
        return kAudio_ParamError;
    graph_notify *r = calloc(1, sizeof *r);
    if (!r)
        return kAudio_MemFullError;
    r->proc = proc, r->ref = ref;
    pthread_mutex_lock(&g->lock);
    r->next = g->notifies;
    g->notifies = r;
    node *head = head_node(g);
    OSStatus err = g->open && head && head->unit ? AudioUnitAddRenderNotify(head->unit, proc, ref) : noErr;
    pthread_mutex_unlock(&g->lock);
    return err;
}

OSStatus AUGraphRemoveRenderNotify(AUGraph g, AURenderCallback proc, void *ref)
{
    if (!g)
        return kAudio_ParamError;
    pthread_mutex_lock(&g->lock);
    for (graph_notify **r = &g->notifies; *r;) {
        if ((*r)->proc == proc && (*r)->ref == ref) {
            graph_notify *gone = *r;
            *r = gone->next;
            free(gone);
        } else
            r = &(*r)->next;
    }
    node *head = head_node(g);
    if (g->open && head && head->unit)
        AudioUnitRemoveRenderNotify(head->unit, proc, ref);
    pthread_mutex_unlock(&g->lock);
    return noErr;
}

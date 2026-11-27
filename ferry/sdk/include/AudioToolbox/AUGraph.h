/* SPDX-License-Identifier: GPL-3.0-or-later
 * Ferry SDK: audio unit graphs (freemac 1.NEXT): audio units opened as the
 * nodes of a graph, each node's output connected to another's input, with
 * an output unit at the head that plays (or, for generic output, renders
 * when the program pulls on it). Written from Apple's public documentation
 * of AUGraph.h; not Apple's header (coreaudio/CAGraph.m). */
#ifndef _FERRY_AUGRAPH_H_
#define _FERRY_AUGRAPH_H_
#include <AudioToolbox/AudioUnit.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef SInt32 AUNode;
typedef struct OpaqueAUGraph *AUGraph;

enum {
    kAUGraphErr_NodeNotFound = -10860,
    kAUGraphErr_InvalidConnection = -10861,
    kAUGraphErr_OutputNodeErr = -10862,
    kAUGraphErr_CannotDoInCurrentContext = -10863,
    kAUGraphErr_InvalidAudioUnit = -10864,
};

typedef struct AudioUnitNodeConnection {
    AUNode sourceNode;
    UInt32 sourceOutputNumber;
    AUNode destNode;
    UInt32 destInputNumber;
} AudioUnitNodeConnection, AUNodeConnection;

typedef struct AUNodeRenderCallback {
    AUNode destNode;
    AudioUnitElement destInputNumber;
    AURenderCallbackStruct cback;
} AUNodeRenderCallback;

enum {
    kAUNodeInteraction_Connection = 1,
    kAUNodeInteraction_InputCallback = 2,
};

typedef struct AUNodeInteraction {
    UInt32 nodeInteractionType;
    union {
        AUNodeConnection connection;
        AUNodeRenderCallback inputCallback;
    } nodeInteraction;
} AUNodeInteraction;

OSStatus NewAUGraph(AUGraph *outGraph);
OSStatus DisposeAUGraph(AUGraph inGraph);

OSStatus AUGraphAddNode(AUGraph inGraph, const AudioComponentDescription *inDescription, AUNode *outNode);
OSStatus AUGraphRemoveNode(AUGraph inGraph, AUNode inNode);
OSStatus AUGraphGetNodeCount(AUGraph inGraph, UInt32 *outNumberOfNodes);
OSStatus AUGraphGetIndNode(AUGraph inGraph, UInt32 inIndex, AUNode *outNode);
OSStatus AUGraphNodeInfo(AUGraph inGraph, AUNode inNode, AudioComponentDescription *outDescription,
                         AudioUnit *outAudioUnit);

OSStatus AUGraphConnectNodeInput(AUGraph inGraph, AUNode inSourceNode, UInt32 inSourceOutputNumber,
                                 AUNode inDestNode, UInt32 inDestInputNumber);
OSStatus AUGraphSetNodeInputCallback(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber,
                                     const AURenderCallbackStruct *inInputCallback);
OSStatus AUGraphDisconnectNodeInput(AUGraph inGraph, AUNode inDestNode, UInt32 inDestInputNumber);
OSStatus AUGraphClearConnections(AUGraph inGraph);
OSStatus AUGraphGetNumberOfInteractions(AUGraph inGraph, UInt32 *outNumInteractions);
OSStatus AUGraphGetInteractionInfo(AUGraph inGraph, UInt32 inInteractionIndex, AUNodeInteraction *outInteraction);
OSStatus AUGraphCountNodeInteractions(AUGraph inGraph, AUNode inNode, UInt32 *outNumInteractions);
OSStatus AUGraphGetNodeInteractions(AUGraph inGraph, AUNode inNode, UInt32 *ioNumInteractions,
                                    AUNodeInteraction *outInteractions);
OSStatus AUGraphUpdate(AUGraph inGraph, Boolean *outIsUpdated);

OSStatus AUGraphOpen(AUGraph inGraph);
OSStatus AUGraphClose(AUGraph inGraph);
OSStatus AUGraphInitialize(AUGraph inGraph);
OSStatus AUGraphUninitialize(AUGraph inGraph);
OSStatus AUGraphStart(AUGraph inGraph);
OSStatus AUGraphStop(AUGraph inGraph);

OSStatus AUGraphIsOpen(AUGraph inGraph, Boolean *outIsOpen);
OSStatus AUGraphIsInitialized(AUGraph inGraph, Boolean *outIsInitialized);
OSStatus AUGraphIsRunning(AUGraph inGraph, Boolean *outIsRunning);
OSStatus AUGraphGetCPULoad(AUGraph inGraph, Float32 *outAverageCPULoad);
OSStatus AUGraphGetMaxCPULoad(AUGraph inGraph, Float32 *outMaxLoad);

OSStatus AUGraphAddRenderNotify(AUGraph inGraph, AURenderCallback inCallback, void *inRefCon);
OSStatus AUGraphRemoveRenderNotify(AUGraph inGraph, AURenderCallback inCallback, void *inRefCon);

#ifdef __cplusplus
}
#endif
#endif

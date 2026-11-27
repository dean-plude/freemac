#include <stdio.h>
#include <string.h>
#include "ferry_metal_abi.h"
struct __ferry_tex;
static char tg[4096];
void *__ferry_tg_alloc(unsigned long size, unsigned long align, int id) { (void)size; (void)align; return tg + id * 1024; }
void ferry_fetch_attr(const void *ctx, int attr, unsigned vid, unsigned iid, int want_int, void *out4) {
  float *o = out4; (void)ctx; (void)iid; (void)want_int;
  if (attr == 0) { o[0] = vid; o[1] = vid * 2; o[2] = 0.5f; o[3] = 1; } else { o[0] = 0.25f; o[1] = 0.75f; o[2] = 0; o[3] = 1; }
}
void __ferry_tex_sample(const struct __ferry_tex *t, const void *s, const float *coord, int ncoord, int layer,
                        int mode, float lodval, const float *grad, const int *offset, int is_int, void *out) {
  float *o = out; o[0] = coord[0]; o[1] = coord[1]; o[2] = 0.5f; o[3] = 1.0f;
}
void __ferry_quad_exchange(const void *val, int bytes, void *all4) { for (int i = 0; i < 4; i++) memcpy((char*)all4 + i*bytes, val, bytes); }
int __ferry_quad_lane(void) { return 0; }
void __ferry_barrier(int f) { (void)f; }
void __ferry_vs_vs_main(const struct ferry_call *, float *);
void __ferry_fs_fs_main(const struct ferry_call *, const float *, float *);
void __ferry_cs_add(const struct ferry_call *);
int __ferry_info_vs_vs_main(struct ferry_slot *, int);
int __ferry_info_fs_fs_main(struct ferry_slot *, int);
int main(void) {
  static struct ferry_call c; float out[64] = {0}, res[40] = {0};
  float uni[20] = {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1, 2,3,4,5};
  c.buffers[1] = uni; c.vertex_id = 3;
  __ferry_vs_vs_main(&c, out);
  printf("pos %g %g %g %g  vary %g %g | %g %g %g | %u\n", out[0], out[1], out[2], out[3], out[16], out[17], out[18], out[19], out[20], *(unsigned*)&out[21]);
  struct ferry_slot s[16]; int n = __ferry_info_vs_vs_main(s, 16);
  for (int i = 0; i < n; i++) printf(" vs slot %s what %d off %d n %d kind %d\n", s[i].tag, s[i].what, s[i].offset, s[i].ncomp, s[i].kind);
  n = __ferry_info_fs_fs_main(s, 16);
  for (int i = 0; i < n; i++) printf(" fs slot %s what %d idx %d off %d n %d kind %d interp %d\n", s[i].tag, s[i].what, s[i].index, s[i].offset, s[i].ncomp, s[i].kind, s[i].interp);
  float in[8] = {0.1f, 0.2f, 1, 0.5f, 0.25f, 0};
  c.stage_in_map[0] = 0; c.stage_in_map[1] = 2; c.stage_in_map[2] = 5;
  c.buffers[0] = uni; static struct ferry_sampler smp; c.samplers[0] = &smp; c.textures[0] = (void*)1;
  __ferry_fs_fs_main(&c, in, res);
  printf("frag %g %g %g %g\n", res[0], res[1], res[2], res[3]);
  float a[4] = {1,2,3,4}, b[4] = {10,20,30,40};
  c.buffers[0] = a; c.buffers[1] = b;
  for (unsigned i = 0; i < 4; i++) { c.grid[0][0] = i; c.grid[FERRY_G_INDEX_IN_GROUP][0] = i; __ferry_cs_add(&c); }
  printf("add %g %g %g %g\n", a[0], a[1], a[2], a[3]);
}

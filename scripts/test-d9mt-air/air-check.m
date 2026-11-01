// air-check <winemetal.so> <shader.ir> <out.metallib>: compiles one shader through the
// prebuilt bridge's AIR compiler, the way the game's shaders reach it, and prints each
// function's VERS tag. With --load it also loads the metallib in Metal (newLibraryWithData).
// Built and run by scripts/test-d9mt-air.sh (x86_64, as winemetal.so runs under Rosetta).
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

// From d9mt's airlib/d9mtair.h (ABI 2); d9mtair_version guards the layout.
#define D9MT_AIR_ABI_VERSION 2u
struct version_params { uint32_t abi_version, reserved; };
struct compile_params {
  uint64_t ir_data, ir_size, entry_name;
  uint32_t flags, spec_count;
  uint64_t spec_data, out_metallib, out_size, out_reflection, out_reflection_size;
  uint32_t ret_status, reserved;
  uint64_t pe_metallib_buffer, pe_metallib_capacity, pe_reflection_buffer, pe_reflection_capacity;
};

// winemetal.so looks this one up in Wine's ntdll at load time; the AIR compiler never calls it.
__attribute__((visibility("default"))) int NtSetEvent(void *event, void *previous) {
  (void)event; (void)previous;
  return 0;
}

static uint64_t u64(const uint8_t *p) { uint64_t v; memcpy(&v, p, 8); return v; }
static uint32_t u32(const uint8_t *p) { uint32_t v; memcpy(&v, p, 4); return v; }
static uint16_t u16(const uint8_t *p) { uint16_t v; memcpy(&v, p, 2); return v; }

// Prints "VERS <air>/<language>" for every function; 0 if the function list parses.
static int print_vers(const uint8_t *d, size_t n) {
  if (n < 40 || memcmp(d, "MTLB", 4) != 0) return 1;
  uint64_t pos = u64(d + 24) + 4, end = u64(d + 24) + u64(d + 32);
  int count = 0;
  if (end > n) return 1;
  while (pos + 4 <= end) {
    uint64_t p = pos + 4, fn_end = pos + u32(d + pos);
    if (fn_end > n || fn_end <= pos) return 1;
    while (p + 6 <= fn_end && memcmp(d + p, "ENDT", 4) != 0) {
      uint16_t size = u16(d + p + 4);
      if (memcmp(d + p, "VERS", 4) == 0 && size >= 8 && p + 14 <= fn_end) {
        printf("VERS %u.%u/%u.%u\n", u16(d + p + 6), u16(d + p + 8), u16(d + p + 10), u16(d + p + 12));
        count++;
      }
      p += 6u + size;
    }
    pos = fn_end;
  }
  return count ? 0 : 1;
}

int main(int argc, char **argv) {
  @autoreleasepool {
    int load = argc == 5 && strcmp(argv[4], "--load") == 0;
    if (argc != 4 && !load) {
      fprintf(stderr, "usage: %s <winemetal.so> <shader.ir> <out.metallib> [--load]\n", argv[0]);
      return 2;
    }
    NSData *ir = [NSData dataWithContentsOfFile:@(argv[2])];
    if (!ir) { fprintf(stderr, "cannot read %s\n", argv[2]); return 1; }
    void *so = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!so) { fprintf(stderr, "dlopen: %s\n", dlerror()); return 1; }
    int (*version)(struct version_params *) = (int (*)(struct version_params *))dlsym(so, "d9mtair_version");
    int (*compile)(struct compile_params *) = (int (*)(struct compile_params *))dlsym(so, "d9mtair_compile");
    if (!version || !compile) { fprintf(stderr, "no d9mtair_version/d9mtair_compile\n"); return 1; }
    struct version_params v = {0};
    version(&v);
    if (v.abi_version != D9MT_AIR_ABI_VERSION) { fprintf(stderr, "d9mtair ABI %u, not %u\n", v.abi_version, D9MT_AIR_ABI_VERSION); return 1; }

    struct compile_params c = {0};
    c.ir_data = (uint64_t)(uintptr_t)ir.bytes;
    c.ir_size = ir.length;
    c.entry_name = (uint64_t)(uintptr_t)"main";
    compile(&c);
    if (c.ret_status != 0 || !c.out_metallib) { fprintf(stderr, "compile status %u\n", c.ret_status); return 1; }
    NSData *lib = [NSData dataWithBytes:(const void *)(uintptr_t)c.out_metallib length:c.out_size];
    if (![lib writeToFile:@(argv[3]) atomically:NO]) { fprintf(stderr, "cannot write %s\n", argv[3]); return 1; }
    if (print_vers(lib.bytes, lib.length) != 0) { fprintf(stderr, "no VERS tags in the metallib\n"); return 1; }

    if (load) {
      id<MTLDevice> device = MTLCreateSystemDefaultDevice();
      if (!device) { printf("load skipped: no Metal device\n"); return 0; }
      dispatch_data_t data = dispatch_data_create(lib.bytes, lib.length, NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
      NSError *error = nil;
      id<MTLLibrary> library = [device newLibraryWithData:data error:&error];
      if (!library) {
        printf("load failed: %s\n", error.localizedDescription.UTF8String ?: "(no error)");
        return 1;
      }
      printf("load ok: %s, functions %s\n", device.name.UTF8String,
             [library.functionNames componentsJoinedByString:@" "].UTF8String);
    }
  }
  return 0;
}

// dump-ir <sm3.bin> <out.ir>: the serialized dxbc-spirv IR that d3d9.dll hands d9mtair_compile,
// built exactly like d9mt's airlib/loopback_main.cpp does before it calls the bridge. It makes
// the .ir files next to it from d9mt's own test shaders; see scripts/test-d9mt-air.sh.
#include <cstdio>
#include <fstream>
#include <vector>

#include <ir/ir_builder.h>
#include <ir/ir_legalize.h>
#include <ir/ir_serialize.h>
#include <sm3/sm3_converter.h>
#include <util/util_byte_stream.h>

int main(int argc, char** argv) {
  if (argc < 3) return 2;
  std::ifstream f(argv[1], std::ios::binary | std::ios::ate);
  if (!f) return 1;
  std::vector<uint8_t> bytecode(size_t(f.tellg()));
  f.seekg(0);
  f.read(reinterpret_cast<char*>(bytecode.data()), std::streamsize(bytecode.size()));
  dxbc_spv::util::ByteReader reader(bytecode.data(), bytecode.size());
  dxbc_spv::sm3::Converter::Options convOptions = {};
  convOptions.name = "main";
  convOptions.includeDebugNames = true;
  dxbc_spv::ir::Builder builder;
  dxbc_spv::sm3::Converter converter(reader, convOptions);
  if (!converter.convertShader(builder)) return 1;
  dxbc_spv::ir::CompileOptions compileOptions = {};
  dxbc_spv::ir::legalizeIr(builder, compileOptions);
  dxbc_spv::ir::Serializer serializer(builder);
  std::vector<uint8_t> blob(serializer.computeSerializedSize());
  if (!serializer.serialize(blob.data(), blob.size())) return 1;
  std::ofstream out(argv[2], std::ios::binary);
  out.write(reinterpret_cast<const char*>(blob.data()), std::streamsize(blob.size()));
  printf("%s: %zu bytes\n", argv[2], blob.size());
  return 0;
}

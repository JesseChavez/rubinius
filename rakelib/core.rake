# All the tasks to manage building the Rubinius core library--which is
# essentially the Ruby core library plus Rubinius-specific files. The core
# bootstraps a Ruby environment to the point that user code can be loaded and
# executed.
#
# The basic rule is that any generated file should be specified as a file
# task, not hidden inside some arbitrary task. Generated files are created by
# rule (e.g. the rule for compiling a .rb file into a .rbc file) or by a block
# attached to the file task for that particular file.
#
# The only tasks should be those names needed by the user to invoke specific
# parts of the build (including the top-level build task for generating the
# entire core library).

require "rakelib/digest_files"

# drake does not allow invoke to be called inside tasks
def core_clean
  rm_rf Dir["**/*.rbc",
           "**/.*.rbc",
           "core/signature.rb",
           "runtime/core",
           "spec/capi/ext/*.{o,sig,#{$dlext}}",
          ],
    :verbose => $verbose
end

# TODO: Build this functionality into the compiler
class KernelCompiler
  def self.compile(file, output, line, transforms)
    compiler = Rubinius::ToolSets::Build::Compiler.new :file, :compiled_file

    parser = compiler.parser
    parser.root Rubinius::ToolSets::Build::AST::Script

    if transforms.kind_of? Array
      transforms.each { |t| parser.enable_category t }
    else
      parser.enable_category transforms
    end

    parser.input file, line

    generator = compiler.generator
    generator.processor Rubinius::ToolSets::Build::Generator

    writer = compiler.writer
    writer.name = output

    compiler.run
  end
end

# The rule for compiling all Ruby core library files
rule ".rbc" do |t|
  source = t.prerequisites.first
  puts "RBC #{source}"
  KernelCompiler.compile source, t.name, 1, [:default, :kernel]
end

# Collection of all files in the runtime core library. Modified by
# various tasks below.
runtime_files = FileList["runtime/platform.conf"]
code_db_files = FileList[
  "runtime/core/contents",
  "runtime/core/data",
  "runtime/core/index",
  "runtime/core/initialize",
  "runtime/core/signature"
]
code_db_scripts = []
code_db_code = []
code_db_data = []

# All the core library files are listed in the `core_load_order`
core_load_order = "core/load_order.txt"
core_files = FileList[]

IO.foreach core_load_order do |name|
  core_files << "core/#{name.chomp}"
end

# Generate file tasks for all core library and load_order files.
def file_task(re, runtime_files, signature, rb, rbc)
  rbc ||= ((rb.sub(re, "runtime") if re) || rb) + "c"

  file rbc => [rb, signature]
  runtime_files << rbc
end

def core_file_task(runtime_files, signature, rb, rbc=nil)
  file_task(/^core/, runtime_files, signature, rb, rbc)
end

# Generate a digest of the Rubinius runtime files
signature_file = "core/signature.rb"

runtime_gems_dir = BUILD_CONFIG[:runtime_gems_dir]
bootstrap_gems_dir = BUILD_CONFIG[:bootstrap_gems_dir]

if runtime_gems_dir and bootstrap_gems_dir
  ffi_files = FileList[
    "#{bootstrap_gems_dir}/**/*.ffi"
  ].each { |f| f.gsub!(/.ffi\z/, '') }

  runtime_gem_files = FileList[
    "#{runtime_gems_dir}/**/*.rb"
  ].exclude("#{runtime_gems_dir}/**/spec/**/*.rb",
            "#{runtime_gems_dir}/**/test/**/*.rb")

  bootstrap_gem_files = FileList[
    "#{bootstrap_gems_dir}/**/*.rb"
  ].exclude("#{bootstrap_gems_dir}/**/spec/**/*.rb",
            "#{bootstrap_gems_dir}/**/test/**/*.rb")

  ext_files = FileList[
    "#{bootstrap_gems_dir}/**/*.{c,h}pp",
    "#{bootstrap_gems_dir}/**/grammar.y",
    "#{bootstrap_gems_dir}/**/lex.c.*"
  ]
else
  ffi_files = runtime_gem_files = bootstrap_gem_files = ext_files = []
end

config_files = FileList[
  "Rakefile",
  "config.rb",
  "rakelib/*.rb",
  "rakelib/*.rake"
]

signature_files = core_files + config_files + runtime_gem_files + ext_files - ffi_files

file signature_file => signature_files do
  # Collapse the digest to a 64bit quantity
  hd = digest_files signature_files
  SIGNATURE_HASH = hd[0, 16].to_i(16) ^ hd[16,16].to_i(16) ^ hd[32,8].to_i(16)

  File.open signature_file, "wb" do |file|
    file.puts "# This file is generated by rakelib/core.rake. The signature"
    file.puts "# is used to ensure that the runtime files and VM are in sync."
    file.puts "#"
    file.puts "Rubinius::Signature = #{SIGNATURE_HASH}"
  end
end

signature_header = "machine/gen/signature.h"

file signature_header => signature_file do |t|
  File.open t.name, "wb" do |file|
    file.puts "#define RBX_SIGNATURE          #{SIGNATURE_HASH}ULL"
  end
end

# Index files for loading a particular version of the core library.
directory(runtime_base_dir = "runtime")
runtime_files << runtime_base_dir

signature = "runtime/signature"
file signature => signature_file do |t|
  File.open t.name, "wb" do |file|
    puts "GEN #{t.name}"
    file.puts Rubinius::Signature
  end
end
runtime_files << signature

# Build the gem files
runtime_gem_files.each do |name|
  file_task nil, runtime_files, signature_file, name, nil
end

# Build the bootstrap gem files
bootstrap_gem_files.each do |name|
  file_task nil, runtime_files, signature_file, name, nil
end

namespace :compiler do
  task :load => ['compiler:generate'] do
    require "rubinius/bridge"
    require "rubinius/code/toolset"

    Rubinius::ToolSets.create :build do
      require "rubinius/code/melbourne"
      require "rubinius/code/processor"
      require "rubinius/code/compiler"
      require "rubinius/code/ast"
    end

    require File.expand_path("../../core/signature", __FILE__)
  end

  task :generate => [signature_file]
end

directory "runtime/core"

class CodeDBCompiler
  def self.m_id
    @m_id ||= 0
    (@m_id += 1).to_s
  end

  def self.compile(file, line, transforms)
    compiler = Rubinius::ToolSets::Build::Compiler.new :file, :compiled_code

    parser = compiler.parser
    parser.root Rubinius::ToolSets::Build::AST::Script

    if transforms.kind_of? Array
      transforms.each { |t| parser.enable_category t }
    else
      parser.enable_category transforms
    end

    parser.input file, line

    generator = compiler.generator
    generator.processor Rubinius::ToolSets::Build::Generator

    compiler.run
  end

  def self.marshal(code)
    marshaler = Rubinius::ToolSets::Build::CompiledFile::Marshal.new
    marshaler.marshal code
  end
end

file "runtime/core/data" => ["runtime/core", core_load_order] + runtime_files do |t|
  puts "CodeDB: writing data..."

  core_files.each do |file|
    id = CodeDBCompiler.m_id

    code_db_code << [id, CodeDBCompiler.compile(file, 1, [:default, :kernel])]

    code_db_scripts << [file, id]
  end

  while x = code_db_code.shift
    id, cc = x

    cc.iseq.opcodes.each_with_index do |value, index|
      if value.kind_of? Rubinius::CompiledCode
        cc.iseq.opcodes[index] = i = CodeDBCompiler.m_id
        code_db_code.unshift [i, value]
      end
    end

    marshaled = CodeDBCompiler.marshal cc

    code_db_data << [id, marshaled]
  end

  File.open t.name, "wb" do |f|
    code_db_data.map! do |m_id, data|
      offset = f.pos
      f.write data

      [m_id, offset, f.pos - offset]
    end
  end
end

file "runtime/core/index" => "runtime/core/data" do |t|
  puts "CodeDB: writing index..."

  File.open t.name, "wb" do |f|
    code_db_data.each { |id, offset, length| f.puts "#{id} #{offset} #{length}" }
  end
end

file "runtime/core/contents" => "runtime/core/data" do |t|
  puts "CodeDB: writing contents..."

  File.open t.name, "wb" do |f|
    code_db_scripts.each { |file, id| f.puts "#{file} #{id}" }
  end
end

file "runtime/core/initialize" => "runtime/core/data" do |t|
  puts "CodeDB: writing initialize..."

  File.open t.name, "wb" do |f|
    code_db_scripts.each { |_, id| f.puts id }
  end
end

file "runtime/core/signature" => signature_file do |t|
  puts "CodeDB: writing signature..."

  File.open t.name, "wb" do |f|
    f.puts Rubinius::Signature
  end
end

desc "Build all core library files (alias for core:build)"
task :core => 'core:build'

namespace :core do
  desc "Build all core library files"
  task :build => ['compiler:load'] + runtime_files + code_db_files

  desc "Delete all .rbc files"
  task :clean do
    core_clean
  end
end

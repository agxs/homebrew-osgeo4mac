class Pdfium < Formula
  ver = "3176".freeze # relates to chromium version

  desc "Google-contributed PDF library (without V8 JavaScript engine)"
  homepage "https://pdfium.googlesource.com/pdfium/"
  url "https://pdfium.googlesource.com/pdfium.git",
      :branch => "chromium/#{ver}"
  version ver
  revision 1

  bottle do
    root_url "https://osgeo4mac.s3.amazonaws.com/bottles"
    cellar :any_skip_relocation
    sha256 "7529a9b9c0856ea9df9182c8801a47e4e9116217b81a3a4e9945eda390245fae" => :sierra
  end

  depends_on "python@2" => :build # gyp doesn't run under 2.6 or lower

  resource "depot_tools" do
    url "https://chromium.googlesource.com/chromium/tools/depot_tools.git"
  end

  def pdfium_build_dir
    "out/Release_x64"
  end

  def copy_file_and_dir_path(dir_search, dst_pathname)
    Dir[dir_search].each do |f|
      dst = dst_pathname/File.dirname(f)
      dst.mkpath
      dst.install(f)
    end
  end

  def install
    # need to move git checkout into gclient solutions directory
    base_install = Dir[".*", "*"] - [".", "..", ".brew_home"]
    (buildpath/"pdfium/").mkpath
    base_install.each { |f| mv f, buildpath/"pdfium/" }

    # install chromium's build tools, includes ninja and gyp
    (buildpath/"depot_tools").install resource("depot_tools")
    ENV.prepend_path "PATH", buildpath/"depot_tools"

    # use pdfium's gyp scripts to create ninja build files.
    ENV["GYP_GENERATORS"] = "ninja"

    system "gclient", "config", "--unmanaged", "--name=pdfium",
           "https://pdfium.googlesource.com/pdfium.git" # @#{pdfium_rev}

    # skip large, unneeded deps
    # TODO: add corpus via optional Pythoon testing
    inreplace "pdfium/DEPS" do |s|
      s.sub! %r{^.*"testing/corpus".*\n.*$}, ""
      s.sub! %r{^.*"third_party/icu".*\n.*$}, ""
      s.sub! %r{^.*"third_party/skia".*\n.*$}, ""
      s.sub! /^.*"v8".*\n.*$/, ""
    end

    system "gclient", "sync", "--no-history" # "--shallow"

    # raise

    cd "pdfium" do
      cwdir = Pathname.new(Dir.pwd)
      # system "./build/install-build-deps.sh" # Linux-only
      (cwdir/pdfium_build_dir).mkpath
      # write out config args
      (cwdir/"#{pdfium_build_dir}/args.gn").write <<~EOS
        # Build arguments go here.
        # See "gn args <out_dir> --list" for available build arguments.
        use_goma=false
        is_debug=false
        pdf_use_skia=false
        pdf_use_skia_paths=false
        pdf_enable_xfa=false
        pdf_enable_v8=false
        pdf_is_standalone=true
        pdf_is_complete_lib=true
        is_component_build=false
        clang_use_chrome_plugins=false
        clang=false
        mac_deployment_target="#{MacOS.version}"
      EOS
      system "gn", "gen", pdfium_build_dir

      # compile release build of pdfium & its test binaries
      system "ninja", "-C", pdfium_build_dir, "pdfium_all"

      # copy header files into a pdfium directory
      copy_file_and_dir_path("core/**/*.h", include/"pdfium")
      copy_file_and_dir_path("fpdfsdk/**/*.h", include/"pdfium")
      (include/"pdfium").install Dir["public/**/*.h"]

      # and 3rd party dependency headers
      (include/"pdfium/third_party/base/numerics").install Dir["third_party/base/numerics/*.h"]
      (include/"pdfium/third_party/base").install Dir["third_party/base/*.h"]

      # test data
      (libexec/"testing/resources").install Dir["testing/resources/*"]

      cd pdfium_build_dir do
        (lib/"pdfium").install Dir["obj/lib*.a"]
        bin.install "pdfium_test", "pdfium_diff"
        (libexec/pdfium_build_dir).install Dir["pdfium_*tests"]
      end
    end
  end

  def caveats; <<~EOS
    For building other software, static libs are located in
      #{opt_lib}/pdfium

    and includes in
      #{opt_include}/pdfium
  EOS
  end

  test do
    system libexec/"#{pdfium_build_dir}/pdfium_unittests"
    system libexec/"#{pdfium_build_dir}/pdfium_embeddertests"
  end
end

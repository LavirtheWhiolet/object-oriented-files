require 'oofiles'
require 'fileutils'


module BuildUtils

  include FileUtils

  # Alias for LocalDirectory#files of LocalDirectory::current.
  def files(*args)
    LocalDirectory.current.files(*args)
  end

  # Alias for LocalDirectory::current.
  def current_dir
    LocalDirectory.current
  end

  alias curdir current_dir

  # Alias for LocalFile.
  #
  # NOTE: It does not conflict with Rake's definition. You may include
  # BuildUtils to top-level scope and both Rake's and BuildUtils' definitions
  # will work fine.
  #
  def file
    LocalFile
  end

  # Alias for LocalDirectory.
  def dir
    LocalDirectory
  end

  # Alias for LocalDirectory.temporary
  def temporary_dir
    LocalDirectory.temporary
  end

  alias temp_dir temporary_dir

  alias tmpdir temporary_dir

  # Alias for TemporaryLocalFile
  def temporary_file
    TemporaryLocalFile
  end

  alias temp_file temporary_file

  alias tmpfile temporary_file

  # Alias for FileSystemEntry::allow_overwrite!().
  def allow_overwrite!
    FileSystemEntry.allow_overwrite!
  end

  # Alias for FileSystemEntry::disallow_overwrite!().
  def disallow_overwrite!
    FileSystemEntry.disallow_overwrite!
  end

  # Alias for FileSystemEntry::allowing_overwrite().
  def allowing_overwrite(&block)
    FileSystemEntry.allowing_overwrite(&block)
  end

  # Alias for MVS::Credentials.
  Credentials = MVS::Credentials

  # writes message to STDERR.
  def log(msg)
    STDERR.puts msg
  end

  # Rake defines its own FileUtils#file. Integrate this file's definition with
  # Rake's one (if needed).
  if defined? Rake::FileTask
    class Rake::FileTask  # :nodoc:
      def method_missing(method_id, *args, &block)
        LocalFile.__send__(method_id, *args, &block)
      end
    end
  end

  class LastBuild

    # returns LastBuild of project with specified name.
    def self.of(project_name)
      new(project_name)
    end

    private_class_method :new

    def initialize(project_name)  # :nodoc:
      #
      @last_build_file = FileSystemEntry.allowing_overwrite do
        filename = "last_build_of_prj_#{project_name.hash}.tmp"
        if not LocalDirectory.temporary.has?(filename)
          LocalFile.new(LocalDirectory.temporary, filename).set_modification_time(Time.mktime 1980)
        else
          LocalDirectory.temporary[filename]
        end
      end
    end

    # Time when the LastBuild has been done.
    #
    # It may be some very old Time if the project has never been built before.
    #
    def time
      @time ||= @last_build_file.modification_time
    end

    # notifies that a build has been performed right now.
    def now!
      @last_build_file.modification_time = @time = Time.now
    end

    # clears any information about this LastBuild.
    def clear!
      @last_build_file.delete()
    end

    alias forget! clear!

  end

end

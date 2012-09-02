require 'rubygems'
gem 'facets', '2.9.2'


# :call-seq:
#   oalias new_method_id => old_method_id
#
# creates alias which always refers to overriden method, not the original one.
#
# Example:
#
#   class X
#
#     def meth
#       puts "X.meth"
#     end
#
#     alias original meth
#     oalias :overriden => :meth
#
#   end
#
#   class Y < X
#
#     def meth
#       puts "Y.meth"
#     end
#
#   end
#
#   Y.new.original    #=> X.meth
#   Y.new.overriden   #=> Y.meth
#
def oalias(arg)
  #
  new_method_id, old_method_id = *arg.to_a[0]
  #
  remove_method(new_method_id) if method_defined?(new_method_id)
  #
  if old_method_id.to_s[-1] == (?=) then
    eval "def #{new_method_id}(*args); self.#{old_method_id}(*args); end"
  else
    eval "def #{new_method_id}(*args, &block); self.#{old_method_id}(*args, &block); end"
  end
end


#
# defines a method to release unmanaged resources such as monitors, files,
# streams etc.
#
# It is recommended to use begin/ensure pattern when using Disposable objects
# to guarantee freeing the resources.
#
# See also Object#using().
#
module Disposable

  #
  # closes/releases unmanaged resources (monitors, streams etc.) held by this
  # Object.
  #
  # <b>Abstract.</b>
  #
  def dispose()
  end

end

#
# executes +block+ and then calls +items+' Disposable#dispose() (regardless
# of the +block+ raising Exception).
#
def using(*items, &block)
  #
  return block.call() if items.empty?
  #
  item = items.pop()
  begin
    using(*items, &block)
  ensure
    item.dispose()
  end
end


class Array

  # <b>Fix.</b>
  #
  # It uses Object#===() for Array's items rather than Object#eql?().
  #
  def ===(other)
    return false if self.size != other.size
    self.zip(other).all? do |self_i, other_i|
      self_i === other_i
    end
  end

end


# Alias for Object. It may be useful in pattern matching (see Array#===()).
Any = Object


#
# executes +block+ once.
#
# Inside the block one may use all constructs allowed inside "while" loop,
# such as "redo".
#
def once(&block)
  while true
    return block.call()
  end
end


#
# raises NotImplementedError telling that operation calling this method is
# not implemented.
#
def not_implemented
  raise NotImplementedError, %Q{Operation not implemented}, caller
end


require 'net/ftp'

module Net

  class FTP

    #
    # Puts the connection into EBCDIC mode, issues the given server-side
    # command (such as "STOR myfile"), reads data from +io+ (beginning from
    # +rest_offset+ if it is given) and sends it to the server. If the
    # optional block is given, it also passes it the data, in chunks of
    # +blocksize+ characters.
    #
    def storebcdic(cmd, io, blocksize = DEFAULT_BLOCKSIZE, rest_offset = nil, &block)
      if rest_offset
        io.seek(rest_offset, IO::SEEK_SET)
      end
      synchronize do
        voidcmd("TYPE E")
        conn = transfercmd(cmd, rest_offset)
        loop do
          buf = io.read(blocksize)
          break if buf == nil
          conn.write(buf)
          yield(buf) if block
        end
        conn.close
        voidresp
      end
    end

    #
    # Puts the connection into EBCDIC mode, issues the given command,
    # and fetches the data returned, passing it to the associated block in
    # chunks of +blocksize+ characters. Note that +cmd+ is a server command
    # (such as "RETR myfile").
    #
    def retrebcdic(cmd, blocksize = DEFAULT_BLOCKSIZE, rest_offset = nil) # :yield: data
      synchronize do
        voidcmd("TYPE E")
        conn = transfercmd(cmd, rest_offset)
        loop do
          data = conn.read(blocksize)
          break if data == nil
          yield(data)
        end
        conn.close
        voidresp
      end
    end

  end

end


# An Object which may be replaced with another Object at runtime.
module Replaceable

  protected

  #
  # replaces this Replaceable with +object+. It returns +object+ (or this,
  # they are the same after this method).
  #
  # <strong>WARNING</strong>: Don't use instance variables and non-public
  # methods of this instance after calling this method!
  #
  # <b>Overridable.</b>
  #
  def become!(object)
    # Disable warnings.
    old_verbose = $VERBOSE
    $VERBOSE = nil
    begin
      # Become a reference to the object.
      begin
        # The object may actually be a reference too. Get actual object.
        object = object.instance_eval { self }
        #
        return object if object.equal? self
        # Clear instance variables.
        instance_variables.each do |instance_variable|
          instance_variable_set(instance_variable, nil)
        end
        # Become the reference!
        @referred_object = object; class << self
          # Undefine all methods.
          eval <<-RUBY
            #{
              instance_methods.map do |method_id|
                "undef #{method_id}"
              end.join("\n")
            }
          RUBY
          # Forward all methods to the referred object.
          def method_missing(method_id, *args, &block) # :nodoc:
            eval <<-RUBY
              # Cache the forwarding.
              def #{method_id}(#{args_string = "*args#{if method_id.to_s[-1] != (?=) then ", &block" end}"})
                @referred_object.#{method_id}(#{args_string})
              end
              # Call the method!
              @referred_object.#{method_id}(#{args_string})
            RUBY
          end
          # Ensure this method is still correct.
          def become!(object) # :nodoc:
            # The object may be a reference too. Get actual object.
            object = object.instance_eval { self }
            # Optimization: The only thing we need is to change the object
            #   this reference refers to.
            @referred_object = object
            # Recache forwardings.
            # (not needed)
            #
            return object
          end
        end
        #
        return object
      end
    ensure
      # Restore warnings.
      $VERBOSE = old_verbose
    end
  end

  # <b>Private.</b>
  def method_missing(method_id, *args, &block)
    super
  end

end


require 'facets/file/ext'

module FileSystemEntry

  include Replaceable

  begin
    @@overwrite_allowed = false
  end

  class << self

    # sets #overwrite_allowed? to true.
    def allow_overwrite!
      @@overwrite_allowed = true
    end

    # sets #overwrite_allowed? to false.
    def disallow_overwrite!
      @@overwrite_allowed = false
    end

    #
    # shows whether FileSystemEntry may overwrite any other FileSystemEntry if
    # it is needed.
    #
    # Default is false.
    #
    def overwrite_allowed?
      @@overwrite_allowed
    end

    # sets #overwrite_allowed? to +value+.
    def overwrite_allowed=(value)
      @@overwrite_allowed = value
    end

    # executes +block+. Inside the +block+ #overwrite_allowed? is true.
    def allowing_overwrite(&block)
      old_overwrite_allowed = self.overwrite_allowed?
      begin
        block.call()
      ensure
        self.overwrite_allowed = old_overwrite_allowed
      end
    end

    #
    # copies +entry+ (FileSystemEntry) to +directory+ as +new_name+ and
    # returns that copy.
    # 
    # +overwrite+ shows whether it is allowed to overwrite any existing
    # FileSystemEntry if needed.
    #
    def copy(entry, directory, new_name, overwrite)
      case [entry, directory]
      when [LocalFile, LocalDirectory]
        
      else
        raise NotImplementedError.new %Q{can not copy #{entry} to #{directory}: copying of #{entry.class} to #{directory.class} is not implemented}
      end
    end
    
    #
    # moves +entry+ (FileSystemEntry) to +directory+ as +new_name+.
    # The difference between moving and copying is that moving preserves
    # #modification_time.
    #
    # +overwrite+ shows whether it is allowed to overwrite any existing
    # FileSystemEntry if needed.
    #
    # It returns +entry+.
    #
    def move(entry, directory, new_name, overwrite)
      case [entry, directory]
      when [LocalFile, LocalDirectory]
        
      else
        # Move by copying and setting modification time.
        begin
          old_modification_time =
            begin
              entry.modification_time
            rescue NotImplementedError
              raise NotImplementedError.new %Q{can not move #{entry} to #{directory}: #{entry.class}.modification_time (or one of its dependent methods) is not implemented}
            end
          copy = FileSystemEntry.copy(directory, new_name, overwrite)
          begin
            copy.modification_time = old_modification_time
          rescue NotImplementedError
            raise NotImplementedError.new %Q{can not complete moving of #{entry} to #{directory}: #{copy.class}.modification_time (or one of its dependent methods) setter is not implemented}
          end
          entry.delete0()  # Oh. :-|
          entry.become!(copy)
        end
      end
      return entry
    end
    
    #
    # copies +entry+ (FileSystemEntry) to +directory+ as +new_name+ in
    # EBCDIC mode.
    #
    # Some systems perform basic copying (#copy_to()) and copying in
    # EBCDIC mode entirely differently (for example, FTP server of
    # IBM mainframes). This method deals with it.
    #
    # +overwrite+ shows whether it is allowed to overwrite any existing
    # FileSystemEntry if needed.
    #
    def copy_as_ebcdic(entry, directory, new_name, overwrite)
      case [entry, directory]
      when [LocalFile, LocalDirectory]
        
      else
        raise NotImplementedError.new %(can not copy #{entry} to #{directory} in EBCDIC mode: copying of #{entry.class} to #{directory.class} in EBCDIC mode is not implemented)
      end
    end

  end

  #
  # allows next operation on this FileSystemEntry to overwrite any
  # FileSystemEntry it needs.
  #
  # It returns this FileSystemEntry.
  #
  def overwrite!
    @overwrite_once = true
    return self
  end

  #
  # moves this FileSystemEntry to +directory+ as +new_name+.
  #
  # It returns this FileSystemEntry.
  #
  def move_to(directory, new_name = name)
    move0(directory, new_name, overwrite?)
  end

  def name=(new_name)
    rename(new_name)
  end

  # :call-seq:
  #   rename(new_name)
  #   rename { |name| ... }
  #
  # changes #name of this FileSystemEntry. If block is given then it is passed
  # with old name and must return new name.
  #
  # It returns this FileSystemEntry.
  #
  def rename(new_name = nil, &block)
    new_name =
      if new_name and not block then new_name
      elsif block and not new_name then block.call(name)
      else raise ArgumentError.new %Q{Either new name or block must be given}
      end
    #
    move0(parent_directory, new_name, overwrite?)
  end

  #
  # changes/returns this FileSystemEntry's extension using File#ext.
  #
  def ext(new_ext = nil)
    if new_ext
      rename(File.ext(name, new_ext))
    else
      return File.ext(name)
    end
  end

  def name=(new_name)
    rename(new_name)
  end

  def copy_as(new_name)
    copy0(parent_directory, new_name, overwrite?)
  end

  def copy_to(directory, new_name = name)
    copy0(directory, new_name, overwrite?)
  end

  # <b>Abstract.</b>
  def name
  end

  #
  # <b>Abstract.</b>
  #
  # <b>Overrides</b> method in superclass.
  #
  def to_s
  end

  #
  # Directory this FileSystemEntry resides in.
  #
  # <b>Abstract.</b>
  #
  def parent_directory
  end

  alias parent_dir parent_directory; oalias :parent_dir => :parent_directory

  alias up parent_directory; oalias :up => :parent_directory

  #
  # deletes this FileSystemEntry.
  #
  def delete()
    # Delete this entry actually.
    delete0()
    # Make this object unusable.
    @self_as_string = self.to_s
    class << self
      instance_methods.each do |method|
        next if %W{__id__ __send__ to_s inspect define_method}
        define_method(method) do |*args|
          raise %Q{#{@self_as_string} is deleted}
        end
      end
    end
    #
    return self
  end

  # <b>Abstract.</b>
  def modification_time
  end

  # <b>Abstract.</b>
  def modification_time=(time)
  end

  # The same as #modification_time=() but returns this FileSystemEntry.
  def set_modification_time(time)
    self.modification_time = time
    return self
  end

  # updates #modification_time with current Time.
  def touch()
    self.modification_time = Time.now
  end

  # :call-seq:
  #   if_modified_since(file)
  #   if_modified_since(dir)
  #   if_modified_since(time)
  #
  # If this FileSystemEntry is modified since +time+ or since +file+/+dir+
  # (FileSystemEntry) was modified then this method returns this
  # FileSystemEntry. Otherwise it returns Nothing.
  #
  def if_modified_since(arg)
    time =
      case arg
      when Time then arg
      when FileSystemEntry then entry = arg; entry.modification_time
      else raise ArgumentError.new %Q{wrong argument (#{arg.inspect} for #{Time} or #{FileSystemEntry})}
      end
    #
    if modification_time > time then return self
    else return Nothing.new; end
  end

  #
  # copies this FileSystemEntry to +directory+ as +new_name+ in
  # EBCDIC mode.
  #
  # Some systems perform basic copying (#copy_to()) and copying in EBCDIC mode
  # entirely differently (for example, IBM mainframes). This method deals with
  # it.
  #
  def copy_as_ebcdic_to(directory, new_name = self.name)
    copy_as_ebcdic0(directory, new_name, overwrite?)
  end
  
  class AlreadyExists < Exception

    def initialize(entry_as_string)
      super("#{entry_as_string} already exists")
    end

  end

  class NotExists < Exception

    def initialize(entry_as_string)
      super("#{entry_as_string} does not exist")
    end

  end

  protected

  #
  # actually deletes this FileSystemEntry. It returns nothing.
  #
  # <b>Abstract.</b>
  #
  def delete0()
  end

  private

  #
  # shows whether it is allowed to overwrite any existing FileSystemEntry-es
  # if needed.
  #
  def overwrite?
    result = FileSystemEntry.overwrite_allowed? || @overwrite_once
    @overwrite_once = false
    return result
  end

end


module TemporaryFileSystemEntry

  include FileSystemEntry, Disposable

  #
  # deletes this TemporaryFileSystemEntry.
  #
  # <b>Overrides</b> method in superclass.
  #
  def dispose()
    delete()
  end

  protected

  #
  # <b>Overrides</b> method in superclass.
  #
  # It also makes +obj+ to be a TemporaryFileSystemEntry.
  #
  def become!(obj)
    super(obj).extend TemporaryFileSystemEntry
  end

end


class AFile

  include FileSystemEntry

  READ = "r"
  WRITE = "w"
  APPEND = "a"

  #
  # opens this AFile. With no block, it returns IO object (a stream) for this
  # AFile. If block is given then it is called with IO as an argument and the IO
  # object is automatically closed after the block terminates. In this case
  # this method returns this AFile.
  #
  # +mode+ is one of AFile's constants.
  #
  def open(mode, &block)
    #
    if block
      io = open0(mode)
      begin block.call(io); ensure io.close(); end
      return self
    #
    else
      return open0(mode)
    end
  end

  def content
    open(READ) { |io| return io.read }
  end

  def content=(new_content)
    open(WRITE) { |io| io.write new_content }
  end

  # is the same as #content=() but returns this AFile.
  def set_content(new_content)
    self.content = new_content
    return self
  end

  # :call-seq:
  #   change_content(new_content)
  #   change_content { |content| ... }
  #
  # changes this AFile's #content. If block is given then it is passed with
  # old content and must return new content.
  #
  # It returns this AFile.
  #
  def change_content(new_content = nil, &block)
    new_content =
      if new_content and not block then new_content
      elsif block and not new_content then block.call(content)
      else raise %Q{Either new content or block must be given}
      end
    #
    self.content = new_content
    return self
  end

  alias read content; oalias :read => :content

  alias write set_content; oalias :write => :set_content

  # Alias for #change_content() (block form).
  def rewrite(&block); change_content(&block); end

  #
  # writes +new_content+ to this AFile only if it differs from old #content.
  #
  # It returns this AFile.
  #
  def write_if_different(new_content)
    if new_content != content then self.content = new_content; end
    return self
  end

  #
  # appends +str+ to this AFile.
  #
  # It returns this AFile.
  #
  def append(str)
    open(APPEND) { |io| io.write str }
    return self
  end

  alias << append; oalias :<< => :append

  #
  # returns TemporaryLocalFile.
  #
  def copy_to_temporary_local_file(new_name_suffix = "", new_name_prefix = "tmp")
    TemporaryLocalFile.copy_from(self, new_name_suffix, new_name_prefix)
  end

  alias copy_to_tmpfile copy_to_temporary_local_file; oalias :copy_to_tmpfile => :copy_to_temporary_local_file

  alias temporary_local_copy copy_to_temporary_local_file; oalias :temporary_local_copy => :copy_to_temporary_local_file

  alias tmp_local_copy copy_to_temporary_local_file; oalias :tmp_local_copy => :copy_to_temporary_local_file

  alias tmp_copy copy_to_temporary_local_file; oalias :tmp_copy => :copy_to_temporary_local_file

  def move_to_temporary_local_file(new_name_suffix = "", new_name_prefix = "tmp")
    move_to(*TemporaryLocalFile.new_location(new_name_suffix, new_name_prefix))
  end

  alias move_to_tmpfile move_to_temporary_local_file; oalias :move_to_tmpfile => :move_to_temporary_local_file

  # :call-seq:
  #   encode(encoding)
  #   encode(from_encoding_name, to_encoding_name)
  #
  # In 1st form it encodes #content in specified Encoding (see
  # Encoding#encode()).
  #
  # In 2nd form it decodes #content from +from_encoding_name+ Encoding and
  # encodes it in +to_encoding_name+ Encoding (see Encoding::new()).
  #
  # It returns this AFile.
  #
  def encode(*args)
    case args.size
    when 1
      encoding = *args
      set_content(encoding.encode(content))
    when 2
      from_encoding_name, to_encoding_name = *args
      set_content(Encoding.encode(from_encoding_name, to_encoding_name, content))
    else
      raise ArgumentError.new %Q{wrong number of arguments (#{args.size} for 1-2)}
    end
  end

  #
  # applies String#gsub() with specified arguments to #content and
  # sets #content to result of the applying.
  #
  # It returns this AFile.
  #
  def gsub(*args, &block)
    rewrite { |content| content.gsub(*args, &block) }
  end

  protected

  #
  # <b>Abstract.</b>
  #
  # It returns IO.
  #
  # +mode+ is one of AFile's constants.
  #
  def open0(mode)
  end

end


require 'facets/kernel/in'

class Nothing

  def self.new()
    #
    class << (result = Object.new) # :nodoc:
      # Remove old methods.
      instance_methods.each { |id| undef_method id unless id.in? %W{__id__ __send__} }
      # Return self on all methods.
      def method_missing(method_id, *args, &block)
        return self
      end
    end
    #
    return result
  end

  # returns Nothing.
  def method_missing(method_id, *args, &block)
    return self
  end

end


class Directory

  include FileSystemEntry, Enumerable

  # :call-seq:
  #   include?(obj)
  #   include?(name)
  #
  # First form is the same as Enumerable#include?().
  #
  # In second form it returns true if this Directory has a FileSystemEntry with
  # specified FileSystemEntry#name.
  #
  def include?(arg)
    case arg
    when String
      name = arg
      begin
        self[name]
        return true
      rescue FileSystemEntry::NotExists
        return false
      end
    else
      super(arg)
    end
  end

  #
  # yields successive FileSystemEntry-es contained in this Directory.
  #
  # +include_hidden+ - whether hidden FileSystemEntry-es (with name starting
  # with "<code>.</code>") are yielded or not.
  #
  # <b>Abstract</b>.
  #
  # <b>Overrides</b> method in superclass.
  #
  def each(include_hidden = false, &block)
  end

  # :call-seq:
  #   has?(what)
  #   has?(name)
  #
  # First form is the same as Enumerable#has?().
  #
  # Second form is alias to #include?().
  #
  def has?(arg)
    case arg
    when String then include?(arg)
    else super(arg)
    end
  end

  #
  # returns a FileSystemEntry with specified FileSystemEntry#name contained
  # in this Directory.
  #
  # <b>Overridable.</b> This implementation uses Enumerable#find() on this
  # Directory.
  #
  def [](name)
    self.find { |entry| entry.name == name } or raise FileSystemEntry::NotExists.new(name)
  end

  #
  # returns AFile-s contained in this Directory.
  #
  def files
    self.select { |entry| entry.is_a? AFile }
  end

  #
  # returns FileSystemEntry-es contained in this Directory.
  #
  def entries
    return self
  end

  protected

  # <b>Overrides</b> method in superclass.
  def copy_as_ebcdic0(directory, new_name, overwrite)
    copy_as_ebcdic_not_implemened(directory)
  end

end


require 'facets/string/quote'
require 'fileutils'

module LocalFileSystemEntry

  include FileSystemEntry

  class << self

    def [](path)
      path = File.expand_path(path)
      # Return an instance corresponding to the path.
      # Optimization: The entry is guaranteed to be there after check. Just create
      #   an instance.
      if File.file?(path) then LocalFile.create(path)
      elsif File.directory?(path) then LocalDirectory.create(path)
      else raise FileSystemEntry::NotExists.new(to_s(path))
      end
    end

    # <b>Overrides</b> method in superclass.
    def included(base) # :nodoc:
      class << base
        # I said, inherit all these elements!
        alias create new
      end
    end

    # :call-seq:
    #   to_s(path)
    #   to_s(local_directory, name)
    #   to_s()
    #
    # 1st form returns LocalFileSystemEntry#to_s of LocalFileSystemEntry with
    # specified LocalFileSystemEntry#path.
    #
    # 2nd form returns LocalFileSystemEntry#to_s of LocalFileSystemEntry
    # with specified LocalFileSystemEntry#name contained in +local_directory+.
    #
    # 3rd form is inherited from superclass.
    #
    def to_s(*args)
      case args.size
      when 0
        super()
      when 1
        path = *args
        path.quote
      when 2
        local_directory, name = *args
        self.to_s(File.join(local_directory.path, name))
      else
        raise ArgumentError.new %Q{wrong number of arguments (#{args.size} for 0-2)}
      end
    end

    # :call-seq:
    #   prepare_destination(path, overwrite)
    #   prepare_destination(local_directory, entry_name, overwrite)
    #
    # prepares specified location so one will be able to safely put
    # LocalFileSystemEntry there: it checks whether the location is occupied,
    # whether it can be overwritten, clears it if needed etc.
    #
    # +overwrite+ is true if any FileSystemEntry at the location can be
    # overwritten.
    #
    # It returns +path+ (either given or calculated by +local_directory+ and
    # +entry_name+).
    #
    # <b>Accessible to</b> FileSystemEntry only.
    #
    def prepare_destination(*args)
      case args.size
      when 2
        path, overwrite = *args
        #
        if File.exists?(path)
          if not overwrite then raise FileSystemEntry::AlreadyExists.new(LocalFileSystemEntry.to_s(path))
          else FileUtils.rm_r(path)
          end
        end
        return path
      when 3
        local_directory, entry_name, overwrite = *args
        prepare_destination(File.join(local_directory.path, entry_name), overwrite)
      else
        raise ArgumentError.new %Q{wrong number of arguments (#{args.size} for 2-3)}
      end
    end

    protected

    # The same as ::new().
    #
    # <b>Inheritable.</b>
    #
    def create(*args); new(*args); end

  end

  attr_reader :path

  # <b>Overrides</b> method in superclass.
  def name
    File.basename(path)
  end

  # <b>Overrides</b> method in superclass.
  def to_s
    LocalFileSystemEntry.to_s(path)
  end

  # <b>Overrides</b> method in superclass.
  def parent_directory
    new_path = File.dirname(path)
    # Optimization: The directory is guaranteed to exist. Just return an
    #   instance of it.
    LocalDirectory.create(new_path)
  end

  # <b>Overrides</b> method in superclass.
  def modification_time
    File.mtime(path)
  end

  # <b>Overrides</b> method in superclass.
  def modification_time=(time)
    File.utime(File.atime(path), time, path)
  end

  protected

  def path=(value)
    @path = value
  end

  private

  #
  # +path+ is initial value for #path.
  #
  def initialize(path)
    @path = path
  end

end


require 'fileutils'

class LocalFile < AFile

  include LocalFileSystemEntry

  class << self

    # :call-seq:
    #   new(directory, name, content = "")
    #   new(path, content = "")
    #
    def new(*args)
      #
      path, content = to_path_and_content(*args)
      # Prepare the actual file.
      LocalFileSystemEntry.prepare_destination(path, FileSystemEntry.overwrite_allowed?)
      if content.empty?
        touch(path)
      else
        File.open(path, "wb") { |io| io.write content }
      end
      # Return the program object for the file.
      return create(path)
    end

    def [](path)
      path = File.expand_path(path)
      raise FileSystemEntry::NotExists.new(LocalFileSystemEntry.to_s(path)) unless File.file?(path)
      #
      return create(path)
    end

    # :call-seq:
    #   new_or_existing(directory, name, content = "")
    #   new_or_existing(path, content = "")
    #
    def new_or_existing(*args)
      begin
        LocalFile[to_path(*args)]
      rescue FileSystemEntry::NotExists
        LocalFile.new(*args)
      end
    end

    alias new? new_or_existing

  end

  protected

  # <b>Overrides</b> method in superclass.
  def copy0(directory, name, overwrite)
    case directory
    when LocalDirectory
      new_path = LocalFileSystemEntry.prepare_destination(directory, name, overwrite)
      FileUtils.cp path, new_path
      # Optimization: The file is guaranteed to be there. Just create an
      #   instance corresponding to it.
      return LocalFile.create(new_path)
    when RAM
      RAM.prepare_destination(name, overwrite)
      return RAMFile.new(name, content)
    when MVS::PartitionedDataset
      dataset = directory
      member_name = name
      #
      new_path = MVS.prepare_destination(dataset, member_name, overwrite)
      dataset.mvs.ftp.putbinaryfile(self.path, new_path)
      return dataset[member_name]
    else
      copy_not_implemented(directory)
    end
  end

  # <b>Overrides</b> of method in superclass.
  def move0(directory, name, overwrite)
    case directory
    when LocalDirectory
      new_path = LocalFileSystemEntry.prepare_destination(directory, name, overwrite)
      FileUtils.mv path, new_path
      # Optimization: The file is guaranteed to be there. Just redirect this
      #   instance to it.
      self.path = new_path
      return self
    else
      super(directory, name, overwrite)
    end
  end

  # <b>Overrides</b> method in superclass.
  def delete0()
    FileUtils.rm path
  end

  # <b>Overrides</b> method in superclass.
  def open0(mode)
    File.open(path, mode + "b")
  end

  # <b>Overrides</b> method in superclass.
  def copy_as_ebcdic0(directory, new_name, overwrite)
    case directory
    when MVS::PartitionedDataset
      dataset = directory
      member_name = new_name
      #
      new_path = MVS.prepare_destination(dataset, member_name, overwrite)
      open(READ) { |io| dataset.mvs.ftp.storebcdic("STOR " + new_path, io) }
      return dataset[member_name]
    else
      copy0(directory, name, overwrite)
    end
  end

  private

  # :call-seq:
  #   to_path_and_content(directory, name, content = "")
  #   to_path_and_content(path, content = "")
  #
  # converts arguments of the first form (if called in the first form) to
  # the second form and returns them.
  #
  def self.to_path_and_content(*args)
    #
    raise ArgumentError.new"wrong number of arguments (#{args.size} for 1-3)" unless (1..3).include?(args.size)
    #
    path =
      if args[0].is_a?(Directory)
        directory, name = *args.shift(2)
        File.join(directory.path, name)
      else
        args.shift
      end
    #
    content = args.shift || ""
    #
    return path, content
  end

  # The same as #to_path_and_content() but does not return content.
  def self.to_path(*args)
    return to_path_and_content(*args)[0]
  end

end


require 'tmpdir'
require 'fileutils'

class LocalDirectory < Directory

  include LocalFileSystemEntry

  class << self

    # :call-seq:
    #   new(directory, name)
    #   new(path)
    #
    def new(*args)
      #
      path = to_path(*args)
      # Create actual directory.
      LocalFileSystemEntry.prepare_destination(path, FileSystemEntry.overwrite_allowed?)
      FileUtils.mkdir_p path
      # Return a program instance for the directory.
      return create(path)
    end

    def [](path)
      path = File.expand_path(path)
      raise FileSystemEntry::NotExists.new(LocalFileSystemEntry.to_s(path)) unless File.directory?(path)
      #
      return create(path)
    end

    # :call-seq:
    #   new_or_existing(directory, name)
    #   new_or_existing(path)
    #
    def new_or_existing(*args)
      begin
        LocalDirectory[to_path(*args)]
      rescue FileSystemEntry::NotExists
        LocalDirectory.new(*args)
      end
    end

    alias new? new_or_existing

    def temporary
      # Optimization: It is guaranteed that the directory is there. Just create an
      #   instance.
      LocalDirectory.create(Dir.tmpdir)
    end

    alias temp temporary

    alias tmp temporary

    def current
      # Optimization: Current directory is guaranteed to be there. Just create an
      #   instance corresponding to it.
      LocalDirectory.create(File.expand_path('.'))
    end

  end

  # <b>Overrides</b> method in superclass.
  def each(include_hidden = false)
    Dir.foreach(path) do |name|
      next if name.squeeze == '.' or (hidden?(name) and not include_hidden)
      entry = LocalFileSystemEntry[File.join(path, name)]
      yield entry
    end
    return self
  end

  # :call-seq:
  #   [](name)
  #   [](*glob_patterns)
  #
  # First form <b>overrides</b> method in superclass.
  #
  # In the second form it returns all FileSystemEntry-es from this Directory
  # and its sub-Directory-es which fit +glob_patterns+. See Dir.glob() for
  # details of what +glob_patterns+ is.
  #
  def [](*args)
    if args.size == 1 and not glob_pattern?(args[0])
      # Optimization: We may find the entry faster.
      name = *args
      return LocalFileSystemEntry[File.join(path, name)]
    end
    #
    glob_patterns = args
    absolute_glob_patterns = glob_patterns.map { |pattern| File.join(path, pattern) }
    return Dir.glob(absolute_glob_patterns).
      reject { |entry| hidden?(entry) }.
      map { |entry| LocalFileSystemEntry[entry] }
  end

  alias / []; oalias :/ => :[]

  # :call-seq:
  #   files
  #   files(*glob_patterns)
  #
  # First form is the same as Directory#files.
  #
  # In second form it returns all AFile-s from this Directory and its
  # sub-Directory-es which fit +glob_patterns+.
  #
  # See Dir.glob() for details of what +glob_patterns+ is.
  #
  def files(*args)
    return super() if args.empty?
    #
    glob_patterns = args
    self[*glob_patterns].select { |entry| entry.is_a? AFile }
  end

  # <b>Optimized version</b> of method in superclass.
  def include?(arg)
    case arg
    when String
      name = arg
      return File.exists?(File.join(path, name))
    else
      super(arg)
    end
  end

  protected

  # <b>Overrides</b> method in superclass.
  def copy0(directory, name, overwrite)
    case directory
    when LocalDirectory
      new_path = LocalFileSystemEntry.prepare_destination(directory, name, overwrite)
      FileUtils.cp_r path, new_path
      # Optimization: The directory is guaranteed to be there. Just create an
      #   instance.
      return LocalDirectory.create(new_path)
    else
      copy_not_implemented(directory)
    end
  end

  # <b>Overrides</b> method in superclass.
  def move0(directory, name, overwrite)
    case directory
    when LocalDirectory
      new_path = prepare_destination(directory.path, name, overwrite)
      FileUtils.mv path, new_path
      # Optimization: The file is guaranteed to be there. Just redirect this
      #   instance to it.
      self.path = new_path
      return self
    else
      super(directory, name, overwrite)
    end
  end

  # <b>Overrides</b> method in superclass.
  def delete0()
    FileUtils.rm_r path
  end

  private

  def hidden?(entry)
    File.basename(entry)[0] == (?.)
  end

  def glob_pattern?(str)
    /[\*\?\[\{]/ === str.gsub(/\\./, "")
  end

  # :call-seq:
  #   to_path(directory, name)
  #   to_path(path)
  #
  def self.to_path(*args)
    case args.size
    when 2
      directory, name = *args
      return File.join(directory.path, name)
    when 1
      return args[0]
    else
      raise ArgumentError.new %Q{wrong number of arguments (#{args.size} for 1-2)}
    end
  end

end


# Alias for LocalDirectory.
LocalDir = LocalDirectory


class TemporaryLocalFile < LocalFile

  include TemporaryFileSystemEntry

  begin
    @@next_temporary_local_file_index = 0
  end

  # returns directory and name for new TemporaryLocalFile.
  def self.new_location(name_suffix = "", name_prefix = "tmp")
    directory = LocalDirectory.temporary
    once do
      name = name_prefix + @@next_temporary_local_file_index.to_s(36) + name_suffix
      if directory.has? name
        @@next_temporary_local_file_index += 1
        redo
      end
      return directory, name
    end
  end

  #
  # creates new TemporaryLocalFile. If +content_func+ is given then
  # the TemporaryLocalFile is created with content returned by the
  # +content_func+.
  #
  def self.new(name_suffix = "", name_prefix = "tmp", &content_func)
    directory, name = new_location(name_suffix, name_prefix)
    content = (if content_func then content_func.call(); end) || ""
    super(directory, name, content)
  end

  def self.copy_from(file, new_name_suffix = "", new_name_prefix = "tmp")
    return file.copy_to(*new_location(new_name_suffix, new_name_prefix)).extend(TemporaryFileSystemEntry)
  end

end


require 'facets/kernel/in'
require 'iconv'

module Encoding

  include Disposable

  #
  # returns Encoding which decodes byte array (in the form of String) from
  # +from_encoding_name+ Encoding and then encodes it in +to_encoding_name+
  # Encoding.
  #
  def self.new(from_encoding_name, to_encoding_name)
    #
    return DummyEncoding.new if from_encoding_name == to_encoding_name
    #
    begin
      iconv = Iconv.new(to_encoding_name, from_encoding_name)
      return SimpleEncoding.new(
        proc { |data| iconv.iconv(data) },
        proc { iconv.close }
      )
    rescue Iconv::InvalidEncoding
      if from_encoding_name.in? %W{IBM-1047 IBM1047} then return IBM1047_TO_ISO88591 >> new("ISO-8859-1", to_encoding_name)
      elsif to_encoding_name.in? %W{IBM-1047 IBM1047} then return new(from_encoding_name, "ISO-8859-1") >> ISO88591_TO_IBM1047
      end
      raise
    end
  end

  #
  # decodes data from +from_encoding_name+ Encoding and then encodes it in
  # +to_encoding_name+ Encoding.
  #
  def self.encode(from_encoding_name, to_encoding_name, data)
    using(encoding = Encoding.new(from_encoding_name, to_encoding_name)) do
      encoding.encode(data)
    end
  end

  #
  # encodes +data+ in this Encoding.
  #
  # <b>Abstract.</b>
  #
  def encode(data)
  end

  #
  # returns Encoding which #encode() of first encodes data in this Encoding
  # and then encodes resultant data in +other+ Encoding.
  #
  def >> (other)
    EncodingsComposition.new([self, other])
  end

  private

  class ::String

    if defined? PATTERN_UTF8 then raise %Q{"#{__FILE__}" must be "required" before "jcode"}; end

    # The same as String#tr but performs per-byte translating (regardless of $KCODE).
    alias tr_bytes tr

    # The same as String#tr! but performs per-byte translating (regardless of $KCODE).
    alias tr_bytes! tr!

  end

end


class DummyEncoding

  include Encoding

  begin
    @@instance = nil
  end

  def self.new()
    # Optimization: All instances of DummyEncoding are the same.
    return @@instance ||= super()
  end

  # <b>Overrides</b> method in superclass.
  #
  # It just returns +data+.
  #
  def encode(data)
    data
  end

  # <b>Overrides</b> method in superclass.
  def dispose()
  end

end


class SimpleEncoding

  include Encoding

  #
  # +encode+ or +encode_+ is a Proc which will be used as #encode() method.
  #
  # +dispose+ is a Proc which will be used as #dispose() method.
  #
  def initialize(encode = nil, dispose = proc { }, &encode_)
    @encode = encode || encode_
    @dispose = dispose
  end

  # <b>Overrides</b> method in superclass.
  def encode(data)
    @encode.call(data)
  end

  # <b>Overrides</b> method in superclass.
  def dispose()
    @dispose.call()
  end

end


module Encoding

  private

  ISO88591_TO_IBM1047 = SimpleEncoding.new { |data|
    data.tr_bytes(
      "\000\001\002\003\234\t\206\177\227\215\216\v\f\r\016\017\020\021\022\023\235\205\b\207\030\031\222\217\034\035\036\037\200\201\202\203\204\n\027\e\210\211\212\213\214\005\006\a\220\221\026\223\224\225\226\004\230\231\232\233\024\025\236\032 \240\342\344\340\341\343\345\347\361\242.<(+|&\351\352\353\350\355\356\357\354\337!$*);^\\-/\302\304\300\301\303\305\307\321\246,%_>?\370\311\312\313\310\315\316\317\314`:\#@'=\"\330abcdefghi\253\273\360\375\376\261\260jklmnopqr\252\272\346\270\306\244\265~stuvwxyz\241\277\320[\336\256\254\243\245\267\251\247\266\274\275\276\335\250\257]\264\327{ABCDEFGHI\255\364\366\362\363\365}JKLMNOPQR\271\373\374\371\372\377\\\\\367STUVWXYZ\262\324\326\322\323\3250123456789\263\333\334\331\332\237",
      "\000\001\002\003\004\005\006\a\b\t\n\v\f\r\016\017\020\021\022\023\024\025\026\027\030\031\032\e\034\035\036\037 !\"\#$%&'()*+,\\-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\177\200\201\202\203\204\205\206\207\210\211\212\213\214\215\216\217\220\221\222\223\224\225\226\227\230\231\232\233\234\235\236\237\240\241\242\243\244\245\246\247\250\251\252\253\254\255\256\257\260\261\262\263\264\265\266\267\270\271\272\273\274\275\276\277\300\301\302\303\304\305\306\307\310\311\312\313\314\315\316\317\320\321\322\323\324\325\326\327\330\331\332\333\334\335\336\337\340\341\342\343\344\345\346\347\350\351\352\353\354\355\356\357\360\361\362\363\364\365\366\367\370\371\372\373\374\375\376\377"
    )
  }

  IBM1047_TO_ISO88591 = SimpleEncoding.new { |data|
    data.tr_bytes(
      "\000\001\002\003\004\005\006\a\b\t\n\v\f\r\016\017\020\021\022\023\024\025\026\027\030\031\032\e\034\035\036\037 !\"\#$%&'()*+,\\-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\\\]^_`abcdefghijklmnopqrstuvwxyz{|}~\177\200\201\202\203\204\205\206\207\210\211\212\213\214\215\216\217\220\221\222\223\224\225\226\227\230\231\232\233\234\235\236\237\240\241\242\243\244\245\246\247\250\251\252\253\254\255\256\257\260\261\262\263\264\265\266\267\270\271\272\273\274\275\276\277\300\301\302\303\304\305\306\307\310\311\312\313\314\315\316\317\320\321\322\323\324\325\326\327\330\331\332\333\334\335\336\337\340\341\342\343\344\345\346\347\350\351\352\353\354\355\356\357\360\361\362\363\364\365\366\367\370\371\372\373\374\375\376\377",
      "\000\001\002\003\234\t\206\177\227\215\216\v\f\r\016\017\020\021\022\023\235\205\b\207\030\031\222\217\034\035\036\037\200\201\202\203\204\n\027\e\210\211\212\213\214\005\006\a\220\221\026\223\224\225\226\004\230\231\232\233\024\025\236\032 \240\342\344\340\341\343\345\347\361\242.<(+|&\351\352\353\350\355\356\357\354\337!$*);^\\-/\302\304\300\301\303\305\307\321\246,%_>?\370\311\312\313\310\315\316\317\314`:\#@'=\"\330abcdefghi\253\273\360\375\376\261\260jklmnopqr\252\272\346\270\306\244\265~stuvwxyz\241\277\320[\336\256\254\243\245\267\251\247\266\274\275\276\335\250\257]\264\327{ABCDEFGHI\255\364\366\362\363\365}JKLMNOPQR\271\373\374\371\372\377\\\\\367STUVWXYZ\262\324\326\322\323\3250123456789\263\333\334\331\332\237"
    )
  }

end


require 'facets/enumerable/every'

class EncodingsComposition

  include Encoding

  def initialize(encodings)
    # Optimization: Unfold first inner composition.
    if encodings.first.is_a? EncodingsComposition
      encodings = encodings.first.encodings + encodings.drop(1)
    end
    # Optimization: Exclude dummy encodings.
    encodings = encodings.reject { |encoding| encoding.is_a? DummyEncoding }
    #
    @encodings = encodings
  end

  # <b>Overrides</b> method in superclass.
  def encode(data)
    @encodings.reduce(data) { |new_data, encoding| encoding.encode(new_data) }
  end

  # <b>Overrides</b> method in superclass.
  def dispose()
    @encodings.every.dispose()
  end

  protected

  # <b>Private.</b>
  attr_reader :encodings

end


# RAM as a Directory.
RAM = RandomAccessMemory = Directory.new


#
# RAM as a Directory.
#
# Note that this is an instance, not a Class (see source code).
#
class << RAM

  #
  # prepares specified location in RAM so one will be able to safely put a
  # FileSystemEntry there: it checks whether the location is occupied, clears it
  # if needed etc.
  #
  # +overwrite+ is true if it is allowed to overwrite any FileSystemEntry at
  # the location.
  #
  # <b>Accessible to</b> FileSystemEntry only.
  #
  def prepare_destination(entry_name, overwrite)
    # Do nothing.
  end

  # <b>Overrides</b> method in superclass.
  def name
    "RAM"
  end

  # <b>Overrides</b> method in superclass.
  def to_s
    name
  end

  # <b>Overrides</b> method in superclass.
  def parent_directory
    nil
  end

  # <b>Overrides</b> method in superclass.
  def each(include_hidden = false)
    not_implemented
    # The proposed implementation is to use ObjectSpace.
  end

  # <b>Overrides</b> method in superclass.
  def modification_time
    not_implemented
  end

  # <b>Overrides</b> method in superclass.
  def modification_time=(value)
    not_implemented
  end

  protected

  # <b>Overrides</b> method in superclass.
  def delete0
    abort  # :D
  end

end


require 'stringio'

# AFile residing in RAM.
class RAMFile < AFile

  def initialize(name = "", content = "")
    @name = name
    @content = content
    @modification_time = Time.now
  end

  # <b>Overrides</b> method in superclass.
  def name
    @name
  end

  # <b>Overrides</b> method in superclass.
  def to_s
    %Q{"#{name}" (RAM)}
  end

  # <b>Overrides</b> method in superclass.
  def parent_directory
    RAM
  end

  # <b>Optimized version</b> of method in superclass.
  def append(str)
    @content << str
    touch()
    return self
  end

  # <b>Optimized version</b> of method in superclass.
  def content
    @content
  end

  # <b>Optimized version</b> of method in superclass.
  def content=(new_content)
    @content = new_content
    touch()
    return new_content
  end

  # <b>Overrides</b> method in superclass.
  def modification_time
    @modification_time
  end

  # <b>Overrides</b> method in superclass.
  def modification_time=(time)
    @modification_time = time
  end

  protected

  # <b>Overrides</b> method in superclass.
  def copy0(directory, new_name, overwrite)
    case directory
    when LocalDirectory
      new_path = LocalFileSystemEntry.prepare_destination(directory, new_name, overwrite)
      return LocalFile.new(new_path, content)
    when RAM
      RAM.prepare_destination(new_name, overwrite)
      return RAMFile.new(new_name, @content.dup)
    when MVS::PartitionedDataset
      dataset = directory
      member_name = new_name
      #
      new_path = MVS.prepare_destination(dataset, member_name, overwrite)
      open(READ) { |io| dataset.mvs.ftp.storbinary("STOR " + new_path, io, Net::FTP::DEFAULT_BLOCKSIZE) }
      return dataset[member_name]
    else
      copy_not_implemented(directory)
    end
  end

  # <b>Overrides</b> method in superclass.
  def move0(directory, new_name, overwrite)
    case directory
    # Optimization: Moving from RAM to RAM means renaming.
    when RAM
      RAM.prepare_destination(new_name, overwrite)
      @name = new_name
      return self
    else
      super(directory, new_name, overwrite)
    end
  end

  # <b>Overrides</b> method in superclass.
  def delete0()
    # Do nothing.
  end

  # <b>Overrides</b> method in superclass.
  def open0(mode)
    unless mode == READ then touch(); end
    StringIO.new(@content, mode)
  end

  # <b>Overrides</b> method in superclass.
  def copy_as_ebcdic0(directory, new_name, overwrite)
    case directory
    when MVS::PartitionedDataset
      dataset = directory
      member_name = new_name
      #
      new_path = MVS.prepare_destination(dataset, member_name, overwrite)
      open(READ) { |io| dataset.mvs.ftp.storebcdic("STOR " + new_path, io) }
      return dataset[member_name]
    else
      copy0(directory, new_name, overwrite)
    end
  end

end


require 'net/ftp'
require 'facets/kernel/tap'

class MVS < Directory

  include Disposable

  class << self

    def [](credentials)
      new(credentials)
    end

    private :new

    # :call-seq:
    #   prepare_destination(partitioned_dataset, member_name, overwrite)
    #   prepare_destination(mvs, sequential_dataset_name, overwrite)
    #
    # prepares specified location at MVS so one will be able to
    # safely put FileSystemEntry there: it checks whether the location is
    # occupied, clears it if needed etc.
    #
    # +overwrite+ is true if it is allowed to overwrite any existing
    # FileSystemEntry-es.
    #
    # It returns MVS path to the location.
    #
    # <b>Accessible to</b> FileSystemEntry only.
    #
    def prepare_destination(*args)
      case args
      when [PartitionedDataset, String, Any]
        dataset, member_name, overwrite = *args
        # If someone called this method then he is going to copy some
        # FileSystemEntry to the location.
        raise NotImplementedError.new %Q{Can not perform copying to #{dataset}: copying to #{dataset.class} with no overwriting is not implemented yet} if not overwrite
        #
        return MVS.path(dataset.name, member_name)
      when [MVS, String, Any]
        mvs, dataset_name, overwrite = *args
        # If someone called this method then he is going to copy some
        # FileSystemEntry to the location.
        raise NotImplementedError.new %Q{Can not perform copying to #{mvs}: copying to #{mvs.class} with no overwriting is not implemented yet} if not overwrite
        #
        return MVS.path(dataset_name)
      else
        raise ArgumentError.new %Q{wrong arguments: #{args.inspect}}
      end
    end

    # :call-seq:
    #   join(dataset_name, member_name)
    #   join(dataset_name)
    #
    # returns MVS path to specified assets.
    #
    # <b>Accessible to</b> MVS, MVS::Entry only.
    #
    def path(dataset_name, member_name = nil)
      if not member_name then %Q{'#{dataset_name}'}
      else %Q{'#{dataset_name}(#{member_name})'}
      end
    end

  end

  def initialize(credentials) # :nodoc:
    @credentials = credentials
  end

  # <b>Overrides</b> method in superclass.
  def each(include_hidden = false, &block)
    not_implemented
  end

  #
  # returns dataset with specified name contained in this MVS.
  #
  # <b>Overrides</b> method in superclass.
  #
  def [](dataset_name, sequential = false)
    if sequential then SequentialDataset[self, dataset_name]
    else PartitionedDataset[self, dataset_name]
    end
      # And pray to your gods that the dataset exists and it is of the specified
      # type.
  end

  alias datasets entries; oalias :datasets => :entries

  alias dataset []; oalias :dataset => :[]

  # <b>Overrides</b> method in superclass.
  def name
    credentials.address
  end

  # <b>Overrides</b> method in superclass.
  def to_s
    name
  end

  # <b>Overrides</b> method in superclass.
  def parent_directory
    nil
  end

  # <b>Overrides</b> method in superclass.
  def modification_time
    not_implemented
  end

  # <b>Overrides</b> method in superclass.
  def modification_time=(time)
    not_implemented
  end

  #
  # Net::FTP connection to this MVS.
  #
  # <b>Accessible to</b> FileSystemEntry only.
  #
  def ftp
    #
    if @ftp and @ftp.closed? then @ftp = nil; end
    #
    @ftp ||=
      Net::FTP.new(credentials.address, credentials.login, credentials.password).
      tap { |ftp| ftp.site 'ISPFSTATS' }
  end

  # <b>Overrides</b> method in superclass.
  def dispose
    (@ftp.close; @ftp = nil) if @ftp
  end

  class Credentials

    #
    # loads Credentials from file.
    #
    # Example of the file:
    #
    #   # Lines starting with "#" are ignored.
    #   ; Lines starting with ";" are ignored as well.
    #   # Empty lines are ignored too.
    #
    #   # address, login, password
    #   mainframe.ibm.com, msdude, 99012x95
    #
    #   # or:
    #   # address, login
    #   mainframe.ibm.com, msdude
    #
    # If password is not found in the file then +password_func+ is passed
    # with address and login and should return the password. If in this case
    # +password_func+ is not given then PasswordNotSpecified is raised.
    # 
    def self.load_from_file(path, &password_func)
      #
      password_func ||= proc { raise PasswordNotSpecified }
      #
      File.open(path) do |io|
        io.each_line do |line|
          #
          line = line.strip
          next if line.empty? or line[0] == ?# or line[0] == ?;
          address, login, password = *line.split(',', 3).every.strip
          #
          raise %Q{Invalid credentials file format: line "#{line}" must be of the form "address, login[, password]"} unless address and login
          password ||= password_func.call(address, login)
          return new(address, login, password)
        end
      end
      raise %Q{Credentials are not found in "#{path}"}
    end

    def initialize(address, login, password)
      @address, @login, @password = address, login, password
    end

    attr_reader :address
    attr_reader :login
    attr_reader :password

    class PasswordNotSpecified < Exception

      def initialize()
        super %Q{Password is not specified}
      end

    end

  end

  module Entry

    include FileSystemEntry

    def initialize(mvs, name)
      @mvs = mvs
      @name = name
    end

    # MVS this MVS::Entry resides in.
    attr_reader :mvs

    # <b>Overrides</b> method in superclass.
    def modification_time
      not_implemented
    end

    # <b>Overrides</b> method in superclass.
    def modification_time=(time)
      not_implemented
    end

    #
    # MVS path to this MVS::Entry.
    #
    # <b>Abstract.</b>
    #
    def path
    end

    # <b>Overrides</b> method in superclass.
    def name
      @name
    end

    # <b>Overrides</b> method in superclass.
    def to_s
      path
    end

  end

  class PartitionedDataset < Directory

    include Entry

    # <b>Accessible to</b> MVS only.
    def self.[](mvs, name)
      new(mvs, name)
    end

    private_class_method :new

    # <b>Overrides</b> method in superclass.
    def path
      MVS.path(name)
    end

    # <b>Overrides</b> method in superclass.
    def parent_directory
      mvs
    end

    # <b>Overrides</b> method in superclass.
    def each(include_hidden = false, &block)
      mvs.ftp.nlst(%Q{'#{name}(*)'}).
        map { |entry|
          member_name = entry[/\((.*?)\)/, 1]
          Member[self, member_name]
        }.each(&block)
    end

    # <b>Overrides</b> method in superclass.
    def [](member_name)
      return Member[self, member_name]
        # And pray to your gods that the member exists.
    end

    # Member-s contained in this PartitionedDataset.
    def members
      self
    end

    protected

    # <b>Overrides</b> method in superclass.
    def copy0(directory, new_name, overwrite)
      copy_not_implemented(directory)
    end

    # <b>Overrides</b> method in superclass.
    def delete0()
      not_implemented
    end

  end

  class SequentialEntry < AFile

    include MVS::Entry

    protected

    # <b>Overrides</b> method in superclass.
    def copy0(directory, new_name, overwrite)
      case directory
      when LocalDirectory
        new_path = LocalFileSystemEntry.prepare_destination(directory, new_name, overwrite)
        mvs.ftp.getbinaryfile(self.path, new_path)
        return LocalFile[new_path]
      when RAM
        RAM.prepare_destination(new_name, overwrite)
        content = ""; mvs.ftp.retrbinary("RETR " + self.path, Net::FTP::DEFAULT_BLOCKSIZE) { |data| content << data }
        return RAMFile.new(new_name, content)
      else
        copy_not_implemented(directory)
      end
    end

    # <b>Overrides</b> method in superclass.
    def delete0()
      begin
        mvs.ftp.delete MVS.path(dataset.name, self.name)
      rescue Net::FTPPermError => e
        if /550 DELE fails\: .*? does not exist/ === e.message then
          # Do nothing. Member is deleted.
        else
          raise e
        end
      end
    end

    # <b>Overrides</b> method in superclass.
    def copy_as_ebcdic0(directory, new_name, overwrite)
      #
      retrebcdic_to_io = lambda do |io|
        mvs.ftp.retrebcdic("RETR " + path) { |data| io << data }
      end
      #
      case directory
      when LocalDirectory
        LocalFileSystemEntry.prepare_destination(directory, new_name, overwrite)
        LocalFile.new(directory, new_name).open(WRITE) { |io| retrebcdic_to_io[io] }
      when RAM
        RAM.prepare_destination(new_name, overwrite)
        RAMFile.new(new_name).open(WRITE) { |io| retrebcdic_to_io[io] }
      end
    end

    # <b>Overrides</b> method in superclass.
    def open0(mode)
      not_implemented
    end

  end

  class Member < SequentialEntry

    # <b>Accessible to</b> MVS::PartitionedDataset only.
    def self.[](partitioned_dataset, name)
      new(partitioned_dataset, name)
    end

    private_class_method :new

    # PartitionedDataset this Member is contained in.
    attr_reader :dataset

    # <b>Overrides</b> method in superclass.
    def path
      MVS.path(dataset.name, self.name)
    end

    # <b>Overrides</b> method in superclass.
    def parent_directory
      dataset
    end

    private

    def initialize(partitioned_dataset, name)
      super(partitioned_dataset.mvs, name)
      @dataset = partitioned_dataset
    end

  end

  class SequentialDataset < SequentialEntry

    # <b>Accessible to</b> MVS only.
    def self.[](mvs, name)
      new(mvs, name)
    end

    private_class_method :new

    # <b>Overrides</b> method in superclass.
    def path
      MVS.path(self.name)
    end

    # <b>Overrides</b> method in superclass.
    def parent_directory
      dataset
    end

  end

  protected

  # <b>Overrides</b> method in superclass.
  def copy0(directory, new_name, overwrite)
    copy_not_implemented(directory)
  end

  # <b>Overrides</b> method in superclass.
  def delete0()
    not_implemented
  end

  private

  # Credentials this MVS is opened with.
  attr_reader :credentials

end


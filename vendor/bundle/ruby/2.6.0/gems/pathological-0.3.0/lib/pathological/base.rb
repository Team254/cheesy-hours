require "pathname"

module Pathological
  PATHFILE_NAME = "Pathfile"

  class PathologicalException < RuntimeError; end
  class NoPathfileException < PathologicalException; end

  # Add paths to the load path.
  #
  # @param [String] load_path the load path to use.
  # @param [Array<String>] paths the array of new load paths (if +nil+, the result of {find_load_paths}).
  def self.add_paths!(load_path = $LOAD_PATH, paths = nil)
    begin
      paths ||= find_load_paths
    rescue NoPathfileException
      STDERR.puts "Warning: using Pathological, but no Pathfile was found."
      return
    end
    paths.each do |path|
      if load_path.include? path
        debug "Skipping <#{path}>, which is already in the load path."
      else
        debug "Adding <#{path}> to load path."
        load_path << path
        @@loaded_paths << path
      end
    end
  end

  # For some pathfile, parse it and find all the load paths that it references.
  #
  # @param [String, nil] pathfile the pathfile to inspect. Uses {find_pathfile} if +nil+.
  # @return [Array<String>] the resulting array of paths.
  def self.find_load_paths(pathfile = nil)
    pathfile ||= find_pathfile
    raise NoPathfileException unless pathfile
    begin
      pathfile_handle = File.open(pathfile)
    rescue Errno::ENOENT
      raise NoPathfileException
    rescue
      raise PathologicalException, "There was an error opening the pathfile <#{pathfile}>."
    end
    parse_pathfile(pathfile_handle)
  end

  # Find the pathfile by searching up from a starting directory. Symlinks are expanded out.
  #
  # @param [String] directory the starting directory. Defaults to the directory containing the running file.
  # @return [String, nil] the absolute path to the pathfile (if it exists), otherwise +nil+.
  def self.find_pathfile(directory = nil)
    # If we're in IRB, use the working directory as the root of the search path for the Pathfile.
    if $0 != __FILE__ && $0 == "irb"
      directory = Dir.pwd
      debug "In IRB -- using the cwd (#{directory}) as the search root for Pathfile."
    end
    return nil if directory && !File.directory?(directory)
    # Find the full, absolute path of this directory, resolving symlinks. If no directory was given, use the
    # directory where the file requiring pathological resides.
    full_path = real_path(directory || requiring_filename)
    current_path = directory ? full_path : File.dirname(full_path)
    loop do
      debug "Searching <#{current_path}> for Pathfile."
      pathfile = File.join(current_path, PATHFILE_NAME)
      if File.file? pathfile
        debug "Pathfile found: <#{pathfile}>."
        return pathfile
      end
      new_path = File.dirname current_path
      if new_path == current_path
        debug "Reached filesystem root, but no Pathfile found."
        return nil
      end
      current_path = new_path
    end
  end

  # Copies directories in pathfile to a destination, such that the destination has no references to
  # directories outside of the destination in the load path.
  #
  # Hierarchy of destination directory:
  #   destination/
  #      Pathfile     # new paths
  #      dependency_directory/
  #         dependency1         # Copied from original location
  #
  # This is very useful for deployment, for example.
  #
  # @param [String] copy_outside_paths the directory to stage dependencies in
  # @param [String] dependency_directory the subdir within destination to put dependencies in
  # @param [String] pathfile_search_path the directory at which to begin the search for the Pathfile by
  #                 walking up the directory tree
  #
  # TODO(ev): Break this function up into a set of more functional primitives
  def self.copy_outside_paths!(destination, options = {})
    options = { :dependency_directory => "pathological_dependencies" }.merge(options)
    saved_exclude_root = @@exclude_root
    begin
      self.excluderoot_mode
      pathfile = self.find_pathfile(options[:pathfile_search_path])
      # Nothing to do if there's no Pathfile
      return unless pathfile && File.file?(pathfile)

      foreign_paths = self.find_load_paths(pathfile).uniq
      return if foreign_paths.empty?

      path_root = File.join(destination, options[:dependency_directory])
      FileUtils.mkdir_p path_root

      # Copy in each path and save the relative paths to write to the rewritten Pathfile. We copy each unique
      # path into the folder not as the basename, but as the longest suffix of the path necessary to make it
      # unique. (Otherwise this won't work if you have two entries with the same basename in the Pathfile,
      # such as "foo/lib" and "bar/lib".)
      common_prefix = find_longest_common_prefix(foreign_paths)
      new_pathfile_paths = foreign_paths.map do |foreign_path|
        path_short_name = foreign_path.gsub(/^#{common_prefix}/, "")
        symlinked_name = File.join(path_root, path_short_name)
        FileUtils.mkdir_p File.split(symlinked_name)[0]
        debug "About to move #{foreign_path} to #{symlinked_name}..."
        copy_directory(foreign_path, symlinked_name)
        File.join(options[:dependency_directory], path_short_name)
      end
      # Overwrite the Pathfile with the new relative paths.
      File.open(File.join(destination, "Pathfile"), "w") do |file|
        new_pathfile_paths.each { |path| file.puts path }
      end
    ensure
      @@exclude_root = saved_exclude_root
    end
  end

  # Convenience functions for the various modes in which Pathological may run.

  def self.debug_mode; @@debug = true; end
  def self.bundlerize_mode
    pathfile = self.find_pathfile
    raise NoPathfileException unless pathfile
    bundle_gemfile = File.join(File.dirname(pathfile), "Gemfile")
    unless File.file? bundle_gemfile
      raise PathologicalException, "No Gemfile found in #{File.dirname(pathfile)}."
    end
    ENV["BUNDLE_GEMFILE"] = bundle_gemfile
  end
  def self.parentdir_mode; @@add_parents = true; end
  def self.noexceptions_mode; @@no_exceptions = true; end
  def self.excluderoot_mode; @@exclude_root = true; end

  # Reset all Pathological options (useful if you want to require a different Pathfile)
  def self.reset!
    # Debug mode -- print out information about load paths
    @@debug = false
    # Parentdir mode -- add unique parents of specified directories.
    @@add_parents = false
    # Noexceptions mode -- don't raise exceptions if the Pathfile contains bad paths
    @@no_exceptions = false
    # Excluderoot mode -- don't add the project root (where the Pathfile lives) to the load path
    @@exclude_root = false

    @@loaded_paths ||= []
    @@loaded_paths.each { |path| $LOAD_PATH.delete path }
    @@loaded_paths = []
  end

  # private module methods

  # Print debugging info
  #
  # @private
  # @param [String] message the debugging message
  # @return [void]
  def self.debug(message); puts "[Pathological Debug] >> #{message}" if @@debug; end

  # Turn a path into an absolute path with no useless parts and no symlinks.
  #
  # @private
  # @param [String] the path
  # @return [String] the absolute real path
  def self.real_path(path); Pathname.new(path).realpath.to_s; end

  # Parse a pathfile and return the appropriate paths.
  #
  # @private
  # @param [IO] pathfile handle to the pathfile to parse
  # @return [Array<String>] array of paths found
  def self.parse_pathfile(pathfile)
    root = File.dirname(real_path(pathfile.path))
    raw_paths = [root]
    pathfile.each do |line|
      # Trim comments
      line = line.split(/#/, 2)[0].strip
      next if line.empty?
      raw_path = Pathname.new(line).absolute? ? line : File.expand_path(File.join(root, line))
      raw_paths << (@@add_parents ? File.dirname(raw_path) : raw_path)
    end

    paths = []
    raw_paths.each do |path|
      unless File.directory? path
        unless @@no_exceptions
          raise PathologicalException, "Bad path in Pathfile: #{path}"
        end
        debug "Ignoring non-existent path: #{path}"
        next
      end
      next if @@exclude_root && File.expand_path(path) == File.expand_path(root)
      paths << path
    end
    @@exclude_root ? paths.reject { |path| File.expand_path(path) == File.expand_path(root) } : paths
  end

  # Find the longest common path prefix amongst a list of paths
  #
  # @private
  # @param [List<String>] a list of paths
  # @return [String] the longest common prefix, or "/"
  def self.find_longest_common_prefix(paths)
    if paths.size == 1
      common_prefix = File.split(paths[0])[0]
    else
      common_prefix = "/"
      paths[0].split("/").reject(&:empty?).each do |part|
        new_prefix = "#{common_prefix}#{part}/"
        break unless paths.all? { |path| path.start_with? new_prefix }
        common_prefix = new_prefix
      end
    end
    common_prefix
  end

  # Copies a directory and all its symlinks to a destination.
  # @private
  def self.copy_directory(source, dest)
    rsync_command = "rsync -r --archive --links --copy-unsafe-links --delete #{source}/ '#{dest}'"
    debug `#{rsync_command}`
  end

  # Searches the call stack for the file that required pathological. If no file can be found, falls back to
  # the currently executing file ($0). This handles the case where the app was launched by another executable
  # (rake, thin, etc.)
  #
  # @return [String] name of file requiring pathological, or the currently executing file.
  def self.requiring_filename
    # Match paths like .../gems/pathological-0.2.2.1/lib/pathological/base.rb and also
    # .../gems/pathological-0.2.2.1/lib/pathological.rb
    pathological_file_pattern = %r{/pathological(/[^/]+|)\.rb}
    requiring_file = Kernel.caller.find do |stack_line|
      if RUBY_VERSION.start_with?("1.9")
        # In Ruby 1.9, top-level files will have the string "top (required)" included in the stack listing.
        stack_line.include?("top (required)") && stack_line !~ pathological_file_pattern
      else
        # In Ruby 1.8, top-level files are listed with their relative path and without a line number.
        stack_line !~ /:\d+:in/ && stack_line !~ pathological_file_pattern
      end
    end
    requiring_file ? requiring_file.match(/(.+):\d+/)[1] : $0 rescue $0
  end

  private_class_method :debug, :real_path, :parse_pathfile, :find_longest_common_prefix, :copy_directory

  # Reset options
  Pathological.reset!
end

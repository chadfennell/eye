require 'celluloid'
require 'yaml'

# MiniDb of pids, manages hash { pid_file => {:pid => pid, :id => identity } }
#   and saves it every 5s to disk if needed

class Eye::PidIdentity
  class << self
    attr_reader :actor

    def setup(filename, interval = 5)
      @actor ||= Actor.new(filename, interval)
    end

    def actor
      @actor ||= Actor.new(Eye::Local.pids_path)
    end

    def set(pid_file, pid)
      actor.set(pid_file, pid)
    end

    def get(pid_file, pid)
      actor.get(pid_file, pid)
    end

    def check(pid_file, pid)
      actor.check(pid_file, pid)
    end

    def clear
      actor.clear
    end

    def debug
      actor.pids
    end
  end

  class Actor
    include Celluloid

    attr_reader :pids

    finalizer :save

    def initialize(filename, interval = 5)
      @filename = filename
      @pids = {}
      @need_sync = false
      load
      every(interval) { sync } if @filename
    end

    def load
      if @filename && pids = read_file(@filename)
        @pids = pids
      end
    end

    def sync
      if @need_sync
        save
        @need_sync = false
      end
    end

    def save
      save_file(@filename, @pids) if @filename
    end

    def get(pid_file, pid)
      h = @pids[pid_file]
      h[:id] if h && h[:pid] == pid
    end

    def set(pid_file, pid)
      if pid
        @pids[pid_file] = { :pid => pid, :id => system_identity(pid) }
      else
        @pids.delete(pid_file)
      end
      @need_sync = true
    end

    # result is [:bad, :ok, :unknown]
    def check(pid_file, pid)
      h = @pids[pid_file]
      return :unknown if !h || h[:pid] != pid

      id = system_identity(h[:pid])
      return :unknown unless id

      id == h[:id] ? :ok : :bad
    end

    def system_identity(pid)
      Eye::SystemResources.start_time_ms(pid)
    end

    def clear
      @pids = {}
      @need_sync = true
    end

  private
    def read_file(filename)
      res = nil
      if File.exists?(filename)
        res = decode(File.read(filename))
        info "pidsdb #{filename} loaded"
      else
        warn "pidsdb #{filename} not found"
      end

      res
    rescue Object => ex
      log_ex(ex)
      nil
    end

    def save_file(filename, data)
      tmp = filename + ".tmp." + "#{rand(100000)}"
      File.open(tmp, 'w') { |f| f.write(encode(data)) }
      FileUtils.mv(tmp, filename)
    rescue Object => ex
      log_ex(ex)
      nil
    end

    def encode(content)
      #Marshal.dump content
      YAML.dump content
    end

    def decode(content)
      #Marshal.load content
      YAML.load content
    end
  end
end

require 'celluloid'

# MiniDb of pids, manages hash { pid => identity }
#   and saves it every 2s to disk if needed

class Eye::PidIdentity
  class << self
    def set_actor(filename, interval = 2)
      @actor = Actor.new(filename, interval)
    end

    def actor
      @actor ||= Actor.new
    end

    def identity(pid)
      actor.identity(pid)
    end

    def set_identity(pid)
      actor.set_identity(pid)
    end

    def remove_identity(pid)
      actor.remove_identity(pid)
    end

    def check_identity(pid)
      actor.check_identity(pid)
    end

    def clear
      @actor.clear if @actor
    end
  end

  class Actor
    include Celluloid

    attr_reader :pids

    def initialize(filename, interval = 2)
      @filename = filename
      @pids = {}
      @need_sync = false
      load
      async.set_identity($$)
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

    def identity(pid)
      @pids[pid]
    end

    def set_identity(pid)
      @pids[pid] = system_identity(pid)
      @need_sync = true
    end

    def remove_identity(pid)
      @pids.delete(pid)
      @need_sync = true
    end

    def system_identity(pid)
      Eye::SystemResources.start_time_ms(pid)
    end

    def clear
      @pids.select! { |pid, value| pid == $$ }
      @need_sync = true
    end

    # nil - identity not found
    # false - bad identity
    # true - ok identity
    def check_identity(pid)
      if id = identity(pid)
        system_identity(pid) == id
      end
    end

  private
    def read_file(filename)
      res = nil
      if File.exists?(filename)
        res = Marshal.load(File.read(filename))
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
      File.open(filename, 'w') { |f| f.write(Marshal.dump(data)) }
    rescue Object => ex
      log_ex(ex)
      nil
    end
  end
end

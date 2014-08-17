module Eye::Process::Monitor

private

  def check_alive_with_refresh_pid_if_needed
    if process_really_running?
      return true

    else
      warn 'process not really running'
      try_update_pid_from_file
    end
  end

  def try_update_pid_from_file
    # if pid file was rewritten
    newpid = load_pid_from_file
    if newpid != self.pid
      info "process <#{self.pid}> changed pid to <#{newpid}>, updating..." if self.pid
      self.pid = newpid

      if process_really_running?
        return true
      else
        warn "process <#{newpid}> was not found"
        return false
      end
    else
      debug 'process was not found'
      return false
    end
  end

  def check_alive
    if up?
      if process_really_running?
        check_pid_identity && check_pid_file
      else
        warn "check_alive: process <#{self.pid}> not found"
        notify :info, 'crashed!'
        clear_pid_file if control_pid? && self.pid && load_pid_from_file == self.pid

        switch :crashed, Eye::Reason.new(:crashed)
      end
    end
  end

  def check_pid_identity
    if Eye::PidIdentity.check(pid_file_ex, self.pid) == :bad
      warn "check_alive: process <#{self.pid}> pid_identity changed"
      notify :info, 'crashed by pid identity!'
      clear_pid_file if control_pid? && self.pid && load_pid_from_file == self.pid

      switch :crashed, Eye::Reason.new(:crashed_pid_identity)
      false
    else
      true
    end
  end

  # check that pid_file still here
  def check_pid_file
    ppid = failsafe_load_pid

    if ppid != self.pid
      msg = "check_alive: pid_file (#{self[:pid_file]}) changed by itself (<#{self.pid}> => <#{ppid}>)"
      if control_pid?
        msg += ", reverting to <#{self.pid}> (the pid_file is controlled by eye)"
        unless failsafe_save_pid
          msg += ", pid_file write failed! O_o"
        end
      else
        changed_ago_s = Time.now - pid_file_ctime

        if ppid == nil
          msg += ", reverting to <#{self.pid}> (the pid_file is empty)"
          unless failsafe_save_pid
            msg += ", pid_file write failed! O_o"
          end

        elsif (changed_ago_s > self[:auto_update_pidfile_grace]) && process_pid_running?(ppid)
          msg += ", trusting this change, and now monitor <#{ppid}>"
          self.pid = ppid

        elsif (changed_ago_s > self[:revert_fuckup_pidfile_grace])
          msg += " over #{self[:revert_fuckup_pidfile_grace]}s ago, reverting to <#{self.pid}>, because <#{ppid}> not alive"
          unless failsafe_save_pid
            msg += ", pid_file write failed! O_o"
          end

        else
          msg += ', ignoring self-managed pid change'
        end
      end

      warn msg
    end
  end

  def check_crash
    if down?
      if self[:keep_alive]
        warn 'check crashed: process is down'

        if self[:restore_in]
          schedule_in self[:restore_in].to_f, :restore, Eye::Reason.new(:crashed)
        else
          schedule :restore, Eye::Reason.new(:crashed)
        end
      else
        warn 'check crashed: process without keep_alive'
        schedule :unmonitor, Eye::Reason.new(:crashed)
      end
    else
      debug 'check crashed: skipped, process is not in down'
    end
  end

  def restore
    start if down?
  end

end

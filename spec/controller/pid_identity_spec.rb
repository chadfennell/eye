require File.dirname(__FILE__) + '/../spec_helper'

describe "Eye::PidIdentity" do

  it "set identity when process daemonized by eye" do
    @process = start_ok_process(C.p1)
    Eye::PidIdentity.identity(@pid).should be
  end

  it "set identity when process self-daemonized" do
    @process = start_ok_process(C.p2)
    Eye::PidIdentity.identity(@pid).should be
  end

  describe "read pid_file" do
    it "process exists, pid_checker no identity, trusting and save identity" do
      cfg = C.p1
      @pid = Eye::System.daemonize("ruby sample.rb", {:environment => {"ENV1" => "SECRET1"},
        :working_dir => cfg[:working_dir], :stdout => @log})[:pid]
      File.open(cfg[:pid_file], 'w'){|f| f.write(@pid) }

      Eye::PidIdentity.identity(@pid).should be_nil

      @process = start_ok_process

      sleep 3

      @process.state_name.should == :up
      Eye::PidIdentity.identity(@pid).should be
      @process.pid.should == @pid
    end

    it "process exists, pid_checker exists, ident is ok" do
      cfg = C.p1
      @pid = Eye::System.daemonize("ruby sample.rb", {:environment => {"ENV1" => "SECRET1"},
        :working_dir => cfg[:working_dir], :stdout => @log})[:pid]
      File.open(cfg[:pid_file], 'w'){|f| f.write(@pid) }

      Eye::PidIdentity.set_identity(@pid)
      Eye::PidIdentity.identity(@pid).should be
      id = Eye::PidIdentity.identity(@pid)

      @process = start_ok_process

      sleep 3

      @process.state_name.should == :up
      Eye::PidIdentity.identity(@pid).should be
      Eye::PidIdentity.identity(@pid).should == id
      @process.pid.should == @pid
    end

    it "process exists, pid_checker exists, ident is bad" do
      cfg = C.p1
      old_pid = Eye::System.daemonize("ruby sample.rb", {:environment => {"ENV1" => "SECRET1"},
        :working_dir => cfg[:working_dir], :stdout => @log})[:pid]
      File.open(cfg[:pid_file], 'w'){|f| f.write(old_pid) }

      id2 = Eye::PidIdentity::Actor.new(C.tmp_file_pids)
      stub(id2).system_identity.with(old_pid) { 2222222 }
      id2.set_identity(old_pid)
      id2.save

      Eye::PidIdentity.actor.load

      Eye::PidIdentity.identity(old_pid).should be

      @process = start_ok_process

      sleep 3

      @process.pid.should_not == old_pid
      @process.state_name.should == :up
      Eye::PidIdentity.identity(old_pid).should be_nil
      Eye::PidIdentity.identity(@process.pid).should be

      @pids << old_pid
    end

    it "process not exists, no identity" do
      cfg = C.p1
      File.open(cfg[:pid_file], 'w'){|f| f.write(125423454) }

      @process = start_ok_process
      @process.state_name.should == :up
      Eye::PidIdentity.identity(@pid).should be
    end

    it "process not exists, identity is, should rewrite" do
      cfg = C.p1
      File.open(cfg[:pid_file], 'w'){|f| f.write(111111) }

      id2 = Eye::PidIdentity::Actor.new(C.tmp_file_pids)
      stub(id2).system_identity.with(111111) { 2222222 }
      id2.set_identity(111111)
      id2.save
      Eye::PidIdentity.actor.load

      Eye::PidIdentity.identity(111111).should be

      @process = start_ok_process
      @process.state_name.should == :up
      Eye::PidIdentity.identity(@pid).should be
      Eye::PidIdentity.identity(111111).should be_nil
    end
  end

  it "when process removed, its removed from pid_checker" do
    @process = start_ok_process
    Eye::PidIdentity.identity(@pid).should be
    @process.delete
    Eye::PidIdentity.identity(@pid).should be_nil
  end

  it "when process stopped, its removed from pid_checker" do
    @process = start_ok_process
    Eye::PidIdentity.identity(@pid).should be
    @process.stop
    Eye::PidIdentity.identity(@pid).should be_nil
  end

  it "when process unmonitored, its removed from pid_checker" do
    @process = start_ok_process
    Eye::PidIdentity.identity(@pid).should be
    @process.unmonitor
    Eye::PidIdentity.identity(@pid).should be_nil
  end

  it "process crashed, identity rewrited" do
    @process = start_ok_process
    Eye::PidIdentity.identity(@pid).should be

    Eye::System.send_signal(@pid, 9)
    sleep 4

    Eye::PidIdentity.identity(@pid).should be_nil
    Eye::PidIdentity.identity(@process.pid).should be
  end

  it "emulate fast change pid" do
    # process die, but within 5s another process up, and get the same pid as old process,
    #   so eye even not seen, that target process died
    # very rare situation

    @process = start_ok_process
    pid = @process.pid

    # тут случайно он умер, и поднялся другой процесс с другой identity
    # эмулируем так:

    sleep 1
    stub(Eye::PidIdentity.actor).system_identity.with(anything) { Eye::SystemResources.start_time_ms(pid) }
    stub(Eye::PidIdentity.actor).system_identity.with(pid) { 2222222 }

    sleep 5

    @process.state_name.should == :up
    @process.pid.should_not == pid

    Eye::PidIdentity.identity(pid).should be_nil
    Eye::PidIdentity.identity(@process.pid).should be
  end

  it "emulate, eye trusting external pid_file change, and update pid, should update identity too, and remove old identity" do
    cfg = C.p2
    start_ok_process(cfg.merge(:auto_update_pidfile_grace => 3.seconds))
    old_pid = @pid

    # up another process
    @pid = Eye::System.daemonize("ruby sample.rb", {:environment => {"ENV1" => "SECRET1"},
      :working_dir => cfg[:working_dir], :stdout => @log})[:pid]
    File.open(cfg[:pid_file], 'w'){|f| f.write(@pid) }

    Eye::PidIdentity.identity(@pid).should be_nil
    Eye::PidIdentity.identity(old_pid).should be

    sleep 5 # here eye should understand that pid-file changed

    @process.pid.should == @pid
    old_pid.should_not == @pid

    @process.load_pid_from_file.should == @pid

    Eye::System.pid_alive?(old_pid).should == true
    Eye::System.pid_alive?(@pid).should == true

    @process.state_name.should == :up

    Eye::PidIdentity.identity(@pid).should be
    Eye::PidIdentity.identity(old_pid).should be_nil

    @pids << old_pid # to gc this process too
  end

  it "when restart all processes, pid_checker update all pids, and save" do
  end

  it "intergration, load, delete, restart, load again, should have valid set of pids" do
  end

  it "eye quit, but pids file was written, than eye load, and all processes just not exists" do
    # should clear old pids from db
  end
end

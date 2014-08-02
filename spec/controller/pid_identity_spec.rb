require File.dirname(__FILE__) + '/../spec_helper'

describe "Eye::PidIdentity" do

  it "set identity when process daemonized by eye"
  it "set identity when process self-daemonized"

  it "read pid_file, process exists, pid_checker no identity, trusting and save identity"
  it "read pid_file, process exists, pid_checker exists, ident is ok"
  it "read pid_file, process exists, pid_checker exists, ident is bad"

  it "when restart all processes, pid_checker update all pids, and save"

  it "when process removed, its removed from pid_checker"
  it "when process stopped, its removed from pid_checker"

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
  end

  it "emulate, eye trusting external pid_file change, and update pid, should update identity too, and remove old identity"

end

require File.dirname(__FILE__) + '/spec_helper'

describe Eye::PidIdentity do
  subject { Eye::PidIdentity }
  before { Eye::PidIdentity.set("/tmp/eye", $$) }

  it "should save" do
    stub(subject.actor).system_identity(1111) { 22222 }

    subject.set("/tmp/1", 1111)
    subject.get("/tmp/1", 1111).should == 22222

    subject.get("/tmp/2", 1111).should == nil
    subject.get("/tmp/1", 1112).should == nil

    sleep 1

    subject.set("/tmp/1", nil)
    subject.get("/tmp/1", 1111).should == nil
  end

  it "should load" do
    stub(subject.actor).system_identity(1111) { 22222 }
    subject.set("/tmp/1", 1111)

    sleep 1

    a = Eye::PidIdentity::Actor.new(C.tmp_file_pids)
    a.get("/tmp/1", 1111).should == 22222
  end

  describe "check" do
    it "check :unknown" do
      subject.check("/tmp/bla", 1234324).should == :unknown
      subject.check("/tmp/eye", 1234324).should == :unknown
      subject.check("/tmp/bla", $$).should == :unknown
    end

    it "check :bad" do
      stub(subject.actor).system_identity($$) { 22222 }
      subject.check("/tmp/eye", $$).should == :bad
    end

    it "check :ok" do
      subject.check("/tmp/eye", $$).should == :ok
    end
  end
end

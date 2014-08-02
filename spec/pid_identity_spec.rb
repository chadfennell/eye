require File.dirname(__FILE__) + '/spec_helper'

describe Eye::PidIdentity do
  subject { Eye::PidIdentity }

  it "should save" do
    stub(subject.actor).system_identity(1111) { 22222 }

    subject.set_identity(1111)
    subject.identity(1111).should == 22222
    subject.identity(11111).should == nil

    sleep 1

    subject.remove_identity(1111)
    subject.identity(1111).should == nil
  end

  it "should load" do
    stub(subject.actor).system_identity(1111) { 22222 }
    subject.set_identity(1111)

    sleep 1

    a = Eye::PidIdentity::Actor.new(C.tmp_file_pids)
    a.identity(1111).should == 22222
  end

  it "check_identity nil" do
    subject.check_identity(1234324).should == nil
  end

  it "check_identity false" do
    stub(subject.actor).system_identity($$) { 22222 }
    subject.check_identity($$).should == false
  end

  it "check_identity true" do
    subject.check_identity($$).should == true
  end
end

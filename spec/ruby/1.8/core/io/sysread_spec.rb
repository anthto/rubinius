require File.dirname(__FILE__) + '/../../spec_helper'

describe "IO#sysread on a file" do
  before :each do
    @file_name = "/tmp/IO_sysread_file" + $$.to_s
    File.open(@file_name, "w") do |f|
      # write some stuff
      f.write("012345678901234567890123456789")
    end
    @file = File.open(@file_name, "r+")
  end
  
  after :each do
    @file.close
    File.delete(@file_name)
  end
  
  it "reads the specified number of bytes from the file" do
    @file.sysread(15).should == "012345678901234"
  end
  
  it "advances the position of the file by the specified number of bytes" do
    @file.sysread(15)
    @file.sysread(5).should == "56789"
  end
  
  it "throws IOError when called immediately after a buffered IO#read" do
    @file.read(15)
    lambda { @file.sysread(5) }.should raise_error(IOError)
  end
  
  it "does not raise error if called after IO#read followed by IO#write" do
    @file.read(5)
    @file.write("abcde")
    lambda { @file.sysread(5) }.should_not raise_error(IOError)
  end
  
  it "does not raise error if called after IO#read followed by IO#syswrite" do
    @file.read(5)
    @file.syswrite("abcde")
    lambda { @file.sysread(5) }.should_not raise_error(IOError)
  end
  
  it "flushes write buffer when called immediately after a buffered IO#write" do
    @file.write("abcde")
    @file.sysread(5).should == "56789"
    File.open(@file_name) do |f|
      f.sysread(10).should == "abcde56789"
    end
  end
end

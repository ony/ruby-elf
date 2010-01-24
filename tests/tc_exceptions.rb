# -*- coding: utf-8 -*-
# Copyright © 2007-2010 Diego E. "Flameeyes" Pettenò <flameeyes@gmail.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this generator; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA

require 'test/unit'
require 'pathname'
require 'elf'

# Test for proper exception handling in the RubyElf library.  This
# test unit should make sure that proper error handling is present
# whenever the file is invalid, contains broken or invalid data, and
# similar.  This test should cover all the possible cases of broken
# ELF files, so that reading a non-ELF file won't cause unexpected
# problems.
class TC_Exceptions < Test::Unit::TestCase
  TestDir = Pathname.new(Elf::BaseTest::TestDir + "invalid/")

  # Define setup and teardown functions to make sure that no
  # descriptors are leaked during the tests. We don't want descriptors
  # to leak when exception happens, otherwise we likely have a bug in
  # the code.
  def setup
    file = File.new(TestDir + "nonelf")
    @fileno_before = file.fileno
    file.close
  end

  def teardown
    file = File.new(TestDir + "nonelf")
    @fileno_after = file.fileno
    file.close

    assert_equal(@fileno_before, @fileno_after,
                 "Descriptor leaked!")
  end

  # Helper to check for exceptions on opening a file.
  def helper_open_exception(exception_class, subpath)
    assert_raise exception_class do
      Elf::File.new(TestDir + subpath)
    end
  end

  # Test behaviour when a file is requested that is not present.
  #
  # Expected behaviour: Errno::ENOENT exception is raised
  def test_nofile
    # Check that the file does not exist or we're going to throw an
    # exception to signal an error in the test.
    if File.exists? TestDir + "notfound"
      raise Exception.new("A file named 'notfound' is present in the #{TestDir.realpath} directory")
    end

    helper_open_exception Errno::ENOENT, "notfound"
  end

  # Test behaviour when a file that is not an ELF file is opened.
  #
  # Expected behaviour: Elf::File::NotAnElf exception is raised.
  def test_notanelf
    helper_open_exception Elf::File::NotAnELF, "nonelf"
  end

  # Test behaviour when a file too short to be an ELF file is opened
  # (that has not enough data to read the four magic bytes at the
  # start of the file).
  #
  # Expected behaviour: Elf::File::NotAnElf exception is raised.
  def test_shortfile
    helper_open_exception Elf::File::NotAnELF, "shortfile"
  end

  # Test behaviour when a file with an invalid ELF class value is
  # opened
  #
  # Expected behaviour: Elf::File::InvalidElfClass exception is
  # raised.
  def test_invalid_elfclass
    helper_open_exception Elf::File::InvalidElfClass, "invalidclass"
  end

  # Test behaviour when a file with an invalid ELF data encoding value
  # is opened
  #
  # Expected behaviour: Elf::File::InvalidDataEncoding exception is
  # raised.
  def test_invalid_encoding
    helper_open_exception Elf::File::InvalidDataEncoding, "invalidencoding"
  end

  # Test behaviour when a file with an unsupported ELF version value
  # is opened
  #
  # Expected behaviour: Elf::File::UnsupportedElfVersion exception is
  # raised.
  def test_unsupported_version
    helper_open_exception Elf::File::UnsupportedElfVersion, "unsupportedversion"
  end

  # Test behaviour when a file with an invalid ELF ABI value is opened
  #
  # Expected behaviour: Elf::File::InvalidOsAbi exception is raised.
  def test_invalid_abi
    helper_open_exception Elf::File::InvalidOsAbi, "invalidabi"
  end

  # Test behaviour when a file with an invalid ELF Type value is
  # opened
  #
  # Expected behaviour: Elf::File::InvalidElfType exception is raised.
  def test_invalid_type
    helper_open_exception Elf::File::InvalidElfType, "invalidtype"
  end

  # Test behaviour when a file with an invalid ELF machine value is
  # opened
  #
  # Expected behaviour: Elf::File::InvalidMachine exception is raised.
  def test_invalid_machine
    helper_open_exception Elf::File::InvalidMachine, "invalidmachine"
  end

  # Test behaviour when opening a named pipe (fifo) path
  #
  # Expected behaviour: Errno::EINVAL exception is raised
  def test_named_pipe
    # Since we cannot add the pipe to the git repository, we've got to
    # create one ourselves :(
    pipepath = Pathname.new(Dir.tmpdir) + "ruby-elf-tests-#{Process.pid}-#{Time.new.strftime("%s")}"
    begin
      pipepath.mkdir
      system("mkfifo #{pipepath}/fifo")

      helper_open_exception Errno::EINVAL, pipepath + "fifo"
    ensure
      pipepath.rmtree
    end
  end

  # Test behaviour when opening a directory path
  #
  # Expected behaviour: Errno::EISDIR exception is raised
  def test_directory
    helper_open_exception Errno::EISDIR, ""
  end

  # Test behaviour when opening a broken link
  #
  # Expected behaviour: Errno::ENOENT exception is raised
  def test_broken_link
    if File.exists? TestDir + "invaliddestination"
      raise Exception.new("A file named 'invaliddestination' is present in the #{TestDir.realpath} directory")
    end

    helper_open_exception Errno::ENOENT, "invalidlink"
  end

  # Test behaviour when a file contains an invalid section type
  # (unknown and outside specific ranges).
  #
  # Expected behaviour: Elf::Section::UnknownType exception is raised
  def test_unknown_section_type
    begin
      elf = Elf::File.new(TestDir + "unknown_section_type")
      elf[11] # We need an explicit request for the corrupted section
    rescue Elf::Section::UnknownType => e
      assert_equal(0x0000ff02, e.type_id,
                   "Wrong type_id reported for unknown section type")

      # We expect an integer as the test file will stop processing
      # _before_ strtab is identified, so there is no string table.
      assert_instance_of(Fixnum, e.section_name,
                         "Non-integer section name provided")
      assert_equal(1, e.section_name,
                   "Wrong section_name reported for unknown section type")
      return
    ensure
      elf.close
    end
    
    flunk("Elf::Section::UnknownType exception not received.")
  end

  # Test behaviour when a file lacks a string table and a section is
  # requested by name.
  #
  # Expected behaviour: Elf::File::MissingStringTable exception is
  # raised
  def test_missing_string_table_request
    elf = Elf::File.new(TestDir + "unknown_section_type")

    assert_raise Elf::File::MissingStringTable do
      elf[".symtab"]
    end

    elf.close
  end

  # Test behaviour when a file lacks a string table and a section is
  # tested by name.
  #
  # Expected behaviour: the method return false, as the section (by
  # name) is certainly not present.
  def test_missing_string_table_test
    elf = Elf::File.new(TestDir + "unknown_section_type")
    assert_equal false, elf.has_section?(".symtab")
    elf.close
  end

  # Test behaviour when a section is requested in a file that does not
  # have it.
  #
  # Expected behaviour: Elf::Section::MissingSection exception is raised
  def test_missing_section
    elf = Elf::File.new(Elf::BaseTest::TestDir + "linux/arm/gcc/dynamic_executable.o")

    # Make sure that the has_section? function behaves correctly and
    # _don't_ throw an exception.
    assert(!elf.has_section?(".data.rel"),
           ".data.rel section present in linux/arm/gcc/dynamic_executable.o")

    assert_raise Elf::File::MissingSection do
      elf[".data.rel"]
    end

    elf.close
  end

  # Test behaviour when a section is requested by index, in a file
  # that does not have such an indexed section.
  #
  # Expected behaviour: Elf::Section:MissingSection exception is
  # raised
  def test_missing_section_index
    elf = Elf::File.new(Elf::BaseTest::TestDir + "linux/arm/gcc/dynamic_executable.o")

    assert_raise Elf::File::MissingSection do
      elf[12300]
    end

    elf.close
  end

  # Test behaviour when trying to check for presence of a section
  # through an invalid type.
  #
  # Expected behaviour: TypeError exception is raised
  def test_has_section_invalid_argument
    elf = Elf::File.new(Elf::BaseTest::TestDir + "linux/arm/gcc/dynamic_executable.o")

    assert_raise TypeError do
      elf.has_section?({:a => :b})
    end

    elf.close
  end

  # Test behaviour when comparing a section instance with something
  # that is not a section.
  #
  # Expected behaviour: TypeError exception is raised
  def test_invalid_section_comparison
    elf = Elf::File.new(Elf::BaseTest::TestDir + "linux/arm/gcc/dynamic_executable.o")

    assert_raise TypeError do
      elf[".ARM.attributes"] == "Foobar"
    end

    elf.close
  end

end

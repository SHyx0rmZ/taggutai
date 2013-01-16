#!/usr/bin/env ruby
# coding: utf-8

require "rspec"
require_relative "class.rb"

describe "Util" do
    describe "clean_path" do
        it 'returns "/a/b/d/e/f" for "/a/b/./c/../d/e/f"' do
            Util.clean_path("/a/b/./c/../d/e/f").should == "/a/b/d/e/f"
            Util.clean_path([ "/a", "b", ".", "c", "..", "d", "e", "f" ]).should == [ "/a", "b", "d", "e", "f" ]
        end

        it 'returns "../../a/c" for "../../a/b/../c"' do
            Util.clean_path("../../a/b/../c").should == "../../a/c"
            Util.clean_path([ "..", "..", "a", "b", "..", "c" ]).should == [ "..", "..", "a", "c" ]
        end
    end
end

describe "Tag" do
    describe "limit" do
        it 'returns [ "a", "de" ] for [ "a", "bc", "de", "fg" ], /^(a|b|d.*)$/' do
            Tag.limit([ "a", "bc", "de", "fg" ], /^(a|b|d.*)$/).should == [ "a", "de" ]
        end

        it 'returns [ "a", "fg" ] for [ "a", "bc", "de", "fg" ], "a", "fg"' do
            Tag.limit([ "a", "bc", "de", "fg" ], "a", "fg").should == [ "a", "fg" ]
        end
    end
end
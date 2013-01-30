#!/usr/bin/env ruby
# coding: utf-8

require 'rspec'
require 'fileutils'
require 'yaml'

file = File.open 'config.spec.yml', 'wb'

file.puts({ 'paths' => { 'working' => 'tmp.spec' } }.to_yaml)
file.close

ARGV[0] = 'config.spec.yml'

require_relative 'class.rb'

describe 'Util' do
    describe 'clean_path' do
        it 'returns "/a/b/d/e/f" for "/a/b/./c/../d/e/f"' do
            Util.clean_path('/a/b/./c/../d/e/f').should == '/a/b/d/e/f'
            Util.clean_path([ '/a', 'b', '.', 'c', '..', 'd', 'e', 'f' ]).should == [ '/a', 'b', 'd', 'e', 'f' ]
        end

        it 'returns "../../a/c" for "../../a/b/../c"' do
            Util.clean_path('../../a/b/../c').should == '../../a/c'
            Util.clean_path([ '..', '..', 'a', 'b', '..', 'c' ]).should == [ '..', '..', 'a', 'c' ]
        end
    end
end

describe 'Tag' do
    describe 'getall' do
        before do
            FileUtils.mkdir_p [ 'a', 'b', 'c/d' ].map { |dir| 'tagtest/' + dir }
        end

        it 'returns [ "a", "b", "c", "c/d" ]' do
            Tag.getall('tagtest').should == [ 'a', 'b', 'c', 'c/d' ]
        end

        after do
            FileUtils.rm_r 'tagtest'
        end
    end

    describe 'limit' do
        it 'returns [ "a", "de" ] for [ "a", "bc", "de", "fg" ], /^(a|b|d.*)$/' do
            Tag.limit([ 'a', 'bc', 'de', 'fg' ], /^(a|b|d.*)$/).should == [ 'a', 'de' ]
        end

        it 'returns [ "a", "fg" ] for [ "a", "bc", "de", "fg" ], "a", "fg"' do
            Tag.limit([ 'a', 'bc', 'de', 'fg' ], 'a', 'fg').should == [ 'a', 'fg' ]
        end
    end
end

describe 'Storage' do
    before do
            Storage.stub! :puts
            Storage.stub! :printf
    end

    describe 'import' do
        before do
            FileUtils.touch "#{IMPORT}/a"
            FileUtils.touch "#{IMPORT}/b"
        end

        it 'creates meta files for imported files' do
            Storage.import
            File.exists?("#{TRACKING}/da39a3ee5e6b4b0d3255bfef95601890afd8070986f7e437faa5a7fce15d1ddcb9eaeaea377667b8").should == true
            File.exists?("#{TRACKING}/da39a3ee5e6b4b0d3255bfef95601890afd80709e9d71f5ee7c92d6dc9e92ffdad17b8bd49418f98").should == true
        end

    end
end

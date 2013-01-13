#!/usr/bin/env ruby
# coding: utf-8

require "digest/sha1"
require "set"

load "names.rb"

def gettags directory
    tags = []

    (Dir.entries(directory, { :encoding => "utf-8" }) - [ "..", "." ]).each do |entry|
        if File.directory? directory + "/" + entry
            tags << entry

            fixed = gettags directory + "/" + entry

            fixed.each do |fix|
                tags << entry + "/" + fix
            end
        end
    end

    tags
end

def limittags tags
    array = []

    ARGV.each do |arg|
        next if arg.eql? "--merge"

        regex = Regexp.new "^#{arg}$"
        matched = false

        tags.each do |tag|
            if tag[regex]
                array << tag

                matched = true
            end
        end

        unless matched
            puts "no matching tag for #{arg}"
        end
    end

    array.uniq
end

def do_getfiles directory
    array = []

    (Dir.entries(directory, { :encoding => "utf-8" }) - [ "..", "." ]).each do |entry|
        if File.file? directory + "/" + entry
            array << entry
        end
    end
end

def getfiles directory, tags, limitedtags
    array = []

    limitedtags.each do |tag|
        array << Set.new(do_getfiles directory + "/tags/" + tag)
    end

    set = array.shift

    if ARGV[0].eql? "--merge"
        array.each do |files|
            set = set.merge files
        end
    else
        array.each do |files|
            set = set.intersection files
        end
    end

    names Dir.pwd + "/original", set.to_a
end

tags = gettags Dir.pwd + "/tags"
limitedtags = limittags tags

unless limitedtags.empty?
    getfiles Dir.pwd, tags, limitedtags
else
    if limitedtags.empty?
        puts "no valid tags specified, tags in database are:"

        tags.each do |tag|
            puts "  #{tag}"
        end
    end
end

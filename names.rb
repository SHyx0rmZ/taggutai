#!/usr/bin/env ruby
# coding: utf-8

require "digest/sha1"

def names directory, arg = ARGV
    (Dir.entries(directory, { :encoding => "utf-8" }) - [ "..", "." ]).each do |entry|
        unless arg.size.eql? 0
            regex = Regexp.new "^(#{arg.join "|"})"

            next unless entry[regex]
        end

        file = File.open directory + "/" + entry, "rb"

        longest = ""

        file.lines.to_a.each do |name|
            longest = name if name.size > longest.size
        end

        file.close

        puts "#{entry[0, 40]} #{longest.force_encoding(Encoding::UTF_8)}"
    end
end

if $0 == __FILE__
    names Dir.pwd + "/original", ARGV
end

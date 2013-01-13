#!/usr/bin/env ruby
# coding: utf-8

require "digest/sha1"

def duplicates directory
    unithash = { "B" => "K", "K" => "M", "M" => "G", "G" => "T", "T" => "P" }

    entries = Dir.entries(directory, { :encoding => "utf-8" }) - [ "..", "." ]

    puts "searching #{entries.size} files for duplicates"

    contenthash = {}
    namehash = {}
    contentdupes = []
    namedupes = []

    entries.each do |entry|
        content = entry[0, 40]
        name = entry[40, 80]

        if contenthash[content]
            contentdupes << content
        else
            contenthash[content] = []
        end

        if namehash[name]
            namedupes << name
        else
            namehash[name] = []
        end

        contenthash[content] << entry
        namehash[name] << entry
    end

    contentdupes.uniq!
    namedupes.uniq!

    # relink files

    contentdupes.each do |dupe|
        hash = Digest::SHA1.new
        names = []

        contenthash[dupe].each do |element|
            file = File.open directory + "/" + element, "rb"

            names = names + file.lines.to_a

            file.close
        end

        names.uniq!
        names.sort!

        names.each do |name|
            hash.update name
        end

        file = File.open directory + "/" + dupe + hash.hexdigest, "wb"

        names.each do |name|
            file.puts name
        end

        file.close

        oldfiles = contenthash[dupe]

        first = oldfiles.shift

        File.rename directory + "/../store/" + first, directory + "/../store/" + dupe + hash.hexdigest
        File.delete directory + "/" + first

        size = File.size directory + "/../store/" + dupe + hash.hexdigest
        unit = "B"

        while size > 1024
            size /= 1024
            unit = unithash[unit]
        end

        puts "saving #{dupe + hash.hexdigest} (#{" " * (4 - size.to_s.size)}#{size}#{unit} * #{oldfiles.size})"

        oldfiles.each do |file|
            File.delete directory + "/" + file
            File.delete directory + "/../store/" + file
        end
    end
end

duplicates Dir.pwd + "/original"

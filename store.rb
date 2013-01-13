#!/usr/bin/env ruby
# coding: utf-8

require "digest/sha1"
require "fileutils"

def clean_path path
    array = path.kind_of? Array

    unless array
        path = path.split "/"
    end

    clean = []

    path.each do |element|
        case element
        when ".."
            clean.delete_at clean.size - 1
        when "."
        else
            clean << element
        end
    end

    unless array
        clean = clean.join "/"
    end

    clean
end

def relative_path path, base
    path = clean_path path.split "/"
    base = clean_path base.split "/"
    difference = 0

    path.each_index do |index|
        unless path[index].eql? base[index]
            difference = index

            break
        end
    end

    path.shift difference
    path.join "/"
end

def process directory, root = directory
    entries = Dir.entries(directory, { :encoding => "utf-8" })
    total = entries.size - 2
    index = 0

    entries.each do |entry|
        if entry[/^\.\.?$/]
            next
        end

        index += 1

        printf "(%#{total.to_s.size}d/%d) ", index, total

        entry = directory + "/" + entry

        if File.directory? entry
            puts "directory (#{relative_path entry, root})"

            process entry, root

            if (Dir.entries(entry) - [ "..", "." ]).size.eql? 0
                Dir.delete entry
            end
        end

        if File.file? entry
            hash = Digest::SHA1.new
            file = File.open entry, "rb"
            target = relative_path entry, root

            until file.eof?
                buffer = file.readpartial 65536

                hash.update buffer
            end

            file.close

            name = hash.hexdigest + Digest::SHA1.new.update(target).hexdigest
            link = root + "/../original/" + name

            unless File.exists? link
                file = File.open link, "wb"

                file.puts target

                file.close
            else
                if File.exists? root + "/../store/" + name
                    File.delete entry

                    puts "already stored #{name} (#{target})"

                    next
                end
            end

            File.rename entry, root + "/../store/" + name
            File.open(root + "/../tags/untagged/" + name, "w").close

            puts "stored #{name} (#{target})"
        end
    end
end

FileUtils.mkdir_p Dir.pwd + "/process"
FileUtils.mkdir_p Dir.pwd + "/tags/untagged"
FileUtils.mkdir_p Dir.pwd + "/original"
FileUtils.mkdir_p Dir.pwd + "/store"

process Dir.pwd + "/process"

#!/usr/bin/env ruby
# coding: utf-8

require "yaml"
require "digest/sha1"
require "fileutils"

config = YAML::load_file "config.yml"
config[:paths] = {} unless config[:paths]

STORAGE = config["paths"]["storage"] or "storage"
TAGS = config["paths"]["tags"] or "tags"
TRACKING = config["paths"]["tracking"] or "meta"
IMPORT = config["paths"]["import"] or "import"

FileUtils.mkdir_p [ STORAGE, TAGS, TRACKING, IMPORT ].map { |dir| "#{Dir.pwd}/#{dir}" }

class Util
    class << self
        def clean_path path
            array = path.kind_of? Array

            path = path.split "/" unless array

            clean = []
            root = true

            path.each do |directory|
                case directory
                when ".."
                    if root
                        clean << directory
                    else
                        clean.delete_at clean.size - 1
                    end
                when "."
                else
                    clean << directory

                    root = false
                end
            end

            clean = clean.join "/" unless array

            clean
        end

        def relative_path path, root
            path = Util.clean_path path.split "/"
            root = Util.clean_path root.split "/"
            difference = 0

            path.each_index do |index|
                unless path[index].eql? root[index]
                    difference = index

                    break
                end
            end

            path.shift difference
            path.join "/"
        end
    end
end

class Tag
    class << self
        def getall directory = "#{Dir.pwd}/#{TAGS}"
            tags = []

            Dir.entries(directory, { :encoding => "utf-8" }).each do |entry|
                next if [ "..", "." ].include? entry

                if File.directory? "#{directory}/#{entry}"
                    tags << entry

                    fixed = Tag.getall "#{directory}/#{entry}"

                    fixed.each do |fix|
                        tags << "#{entry}/#{fix}"
                    end
                end
            end

            tags.sort
        end

        def limit tags, *search
            array = []

            search.each do |regex|
                regex = Regexp.new "^(#{regex}$)" unless regex.kind_of? Regexp

                tags.each do |tag|
                    if tag[regex]
                        array << tag
                    end
                end
            end

            array.uniq
        end
    end
end

class Storage
    class << self
        def import directory = "#{Dir.pwd}/#{IMPORT}", root = directory
            entries = Dir.entries(directory, { :encoding => "utf-8" })
            total = entries.size - 2
            index = 0

            entries.each do |entry|
                next if [ "..", "." ].include? entry

                index += 1
                entry = "#{directory}/#{entry}"

                printf "(%#{total.to_s.size}d/%d) ", index, total

                if File.directory? entry
                    Storage.import entry, root

                    if (Dir.entries(entry) - [ "..", "." ]).size.eql? 0
                        Dir.delete entry
                    end
                end

                if File.file? entry
                    hash = Digest::SHA1.new
                    file = File.open entry, "rb"
                    target = Util.relative_path entry, root

                    until file.eof?
                        buffer = file.readpartial 65536

                        hash.update buffer
                    end

                    file.close

                    name = hash.hexdigest + Digest::SHA1.new.update(target).hexdigest
                    link = "#{root}/../#{TRACKING}/#{name}"
                    duplicate = false

                    unless File.exists? link
                        file = File.open link, "wb"

                        file.puts target
                        file.close
                    else
                        if File.exists? "#{root}/../#{STORAGE}/#{name}"
                            File.delete entry

                            duplicate = true

                            next
                        end
                    end

                    File.rename entry, "#{root}/../#{STORAGE}/#{name}"
                    File.open("#{root}/../#{TAGS}/untagged/#{name}", "w").close

                    puts "stored#{duplicate ? " duplicate " : " "}#{name} (#{target})"
                end
            end
        end
    end
end

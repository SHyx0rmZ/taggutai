#!/usr/bin/env ruby
# coding: utf-8

require 'yaml'
require 'digest/sha1'
require 'fileutils'

path = (ARGV[0] and File.exists?(ARGV[0])) ? ARGV[0] : 'config.yml'

config = YAML::load_file path
config[:paths] = {} unless config[:paths]

WORKING = (config['paths']['working'] or Dir.pwd)
STORAGE = "#{WORKING}/" + (config['paths']['storage'] or 'storage')
TAGS = "#{WORKING}/" + (config['paths']['tags'] or 'tags')
TRACKING = "#{WORKING}/" + (config['paths']['tracking'] or 'meta')
IMPORT = "#{WORKING}/" + (config['paths']['import'] or 'import')
OPTIONS = (config['options'] or {})

FileUtils.mkdir_p [ STORAGE, TAGS, TRACKING, IMPORT, "#{TAGS}/untagged" ]

class DuplicateFileException < Exception
end

class FileNotFoundException < Exception
end

class Util
    class << self
        def clean_path path
            array = path.kind_of? Array

            path = path.split '/' unless array

            clean = []
            root = true

            path.each do |directory|
                case directory
                when '..'
                    if root
                        clean << directory
                    else
                        clean.delete_at clean.size - 1
                    end
                when '.'
                else
                    clean << directory

                    root = false
                end
            end

            clean = clean.join '/' unless array

            clean
        end

        def relative_path path, root
            path = Util.clean_path path.split '/'
            root = Util.clean_path root.split '/'
            difference = 0

            path.each_index do |index|
                unless path[index].eql? root[index]
                    difference = index

                    break
                end
            end

            path.shift difference
            path.join '/'
        end
    end
end

class Tag
    class << self
        def getall directory = TAGS
            tags = []

            Dir.entries(directory, { :encoding => 'utf-8' }).each do |entry|
                next if [ '..', '.' ].include? entry

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
        def import directory = IMPORT, root = directory
            entries = Dir.entries(directory, { :encoding => 'utf-8' })
            total = entries.size - 2
            index = 0

            entries.each do |entry|
                next if [ '..', '.' ].include? entry

                index += 1
                entry = "#{directory}/#{entry}"

                printf "(%#{total.to_s.size}d/%d) ", index, total

                if File.directory? entry
                    Storage.import entry, root

                    if (Dir.entries(entry) - [ '..', '.' ]).size.eql? 0
                        Dir.delete entry
                    end
                end

                if File.file? entry
                    hash = Digest::SHA1.new
                    file = File.open entry, 'rb'
                    target = Util.relative_path entry, root

                    until file.eof?
                        buffer = file.readpartial 65536

                        hash.update buffer
                    end

                    file.close

                    name = hash.hexdigest + Digest::SHA1.new.update(target).hexdigest
                    link = "#{TRACKING}/#{name}"
                    duplicate = false

                    Meta.create name, target unless Meta.has? name

                    if Storage.has? name
                        File.delete entry

                        puts "stored duplicate #{name} (#{target})"
                    else
                        Storage.store name, entry

                        puts "stored #{name} (#{target})"
                    end
                end
            end

            unless OPTIONS['nomerge']
                Meta.duplicates.each do |dupe|
                    Meta.merge dupe
                end
            end
        end

        def has? id
            File.exists? "#{STORAGE}/#{id[0...40]}"
        end

        def store id, path
            raise DuplicateFileException if Storage.has? id

            File.rename path, "#{STORAGE}/#{id[0...40]}"
            FileUtils.touch "#{TAGS}/untagged/#{id[0...40]}"
        end
    end
end

class Meta
    class << self
        def has? id
            result = true
            result = false unless Dir.exists? "#{TRACKING}/#{id[0...40]}"
            result = false unless File.exists? "#{TRACKING}/#{id[0...40]}/#{id[40...80]}"
            result

        end

        def create id, filename
            dirname = id[0...40]
            basename = id[40...80]

            FileUtils.mkdir_p "#{TRACKING}/#{dirname}" unless Dir.exists? "#{TRACKING}/#{dirname}"

            raise DuplicateFileException if Meta.has? id

            file = File.open "#{TRACKING}/#{dirname}/#{basename}", 'wb'
            file.puts filename
            file.close
        end

        def merge id
            hash = Digest::SHA1.new
            names = []

            raise FileNotFoundException unless Meta.has? id

            Dir.entries("#{TRACKING}/#{id[0...40]}", { :encoding => 'utf-8' }).each do |entry|
                next if [ '..', '.' ].include? entry

                file = File.open "#{TRACKING}/#{id[0...40]}/#{entry}", 'rb'
                names += file.lines.to_a
                file.close
            end

            names.uniq!
            names.sort!

            names.each do |name|
                hash.update name
            end

            file = File.open "#{TRACKING}/#{id[0...40]}/#{hash.hexdigest}", 'wb'

            names.each do |name|
                file.puts name
            end

            file.close

            Dir.entries("#{TRACKING}/#{id[0...40]}", { :encoding => 'utf-8' }).each do |entry|
                next if [ '..', '.', hash.hexdigest ].include? entry

                FileUtils.rm "#{TRACKING}/#{id[0...40]}/#{entry}"
            end
        end

        def duplicates
            duplicates = []

            Dir.entries(TRACKING, { :encoding => 'utf-8' }).each do |file|
                next if [ '..', '.' ].include? file

                duplicates << file unless Dir.entries("#{TRACKING}/#{file}", { :encoding => 'utf-8' }).size.eql? 3
            end

            duplicates
        end
    end
end

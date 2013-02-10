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

FileUtils.mkdir_p [ STORAGE, TAGS, TRACKING, IMPORT, "#{TAGS}/taggutai/untagged", "#{TAGS}/taggutai/unmerged" ]

class DuplicateFileException < Exception
end

class FileNotFoundException < Exception
end

class Dir
    class << self
        def reduced_entries path
            nil unless File.exists? path and File.directory? path and File.executable? path and File.readable? path

            Dir.entries(path, { :encoding => 'utf-8' }) - [ '..', '.' ]
        end

        def each_status_and_entry path
            entries = Dir.reduced_entries path
            total = entries.size
            index = 0

            entries.each do |entry|
                next if [ '..', '.' ].include? entry

                yield "(%#{total.to_s.size}d/%d)" % [ index += 1, total ], "#{path}/#{entry}"
            end
        end
    end
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

            Dir.each_status_and_entry(directory) do |status, entry|
                if File.directory? entry
                    tags << Util.relative_path(entry, directory)

                    fixed = Tag.getall entry

                    fixed.each do |fix|
                        tags << "#{Util.relative_path entry, directory}/#{fix}"
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

        def create id, tag
            FileUtils.mkdir_p "#{TAGS}/#{tag}"
            FileUtils.mkdir_p "#{TRACKING}/#{id[0...40]}"
            FileUtils.touch "#{TAGS}/#{tag}/#{id[0...40]}"

            file = File.open "#{TRACKING}/#{id[0...40]}/tags", 'ab'
            file.puts tag
            file.close
        end

        def delete id, tag
            tags = File.readlines "#{TRACKING}/#{id[0...40]}/tags"
            tags.delete "#{tag}\n"

            File.write "#{TRACKING}/#{id[0...40]}/tags", tags.join
            FileUtils.rm "#{TAGS}/#{tag}/#{id[0...40]}"
            FileUtils.rm_r "#{TAGS}/#{tag}" if Dir.reduced_entries("#{TAGS}/#{tag}").size.eql? 0
        end

        def list id
            tags = []

            if File.exists? "#{TRACKING}/#{id[0...40]}/tags"
                file = File.open "#{TRACKING}/#{id[0...40]}/tags", 'rb'

                file.lines.each do |line|
                    tags << line[0...-1]
                end

                file.close
            end

            tags
        end

        def find tag
            files = []

            Dir.each_status_and_entry("#{TAGS}/#{tag}") do |status, entry|
                files << File.basename(entry)
            end

            files
        end
    end
end

class Storage
    class << self
        def hash path
            hash = Digest::SHA1.new
            file = File.open path, 'rb'

            until file.eof?
                buffer = file.readpartial 65536

                hash.update buffer
            end

            file.close

            hash.hexdigest
        end

        def import_symlinks directory, root
            Dir.each_status_and_entry(directory) do |status, entry|
                print status

                if File.directory? entry
                    Storage.import_symlinks entry, root if File.executable? entry
                elsif File.symlink? entry
                    sym = entry

                    while File.symlink? sym and not File.directory? sym
                        if File.readlink(sym).start_with? "/"
                            sym = File.readlink sym
                        else
                            sym = "#{File.dirname sym}/#{File.readlink sym}"
                        end

                        sym = Util.clean_path sym
                    end

                    entry = Util.relative_path entry, root

                    if File.exists? sym
                        Meta.create Storage.hash(sym), entry
                        Tag.create Storage.hash(sym), entry
                        Tag.create Storage.hash(sym), 'taggutai/unmerged'
                    end

                    puts " folllowed symlink (#{entry})"
                end
            end
        end

        def delete_symlinks directory, root
            Dir.each_status_and_entry(directory) do |status, entry|
                if File.symlink? entry
                    FileUtils.rm_f entry
                elsif File.directory? entry
                    Storage.delete_symlinks entry, root if File.executable? entry

                    FileUtils.rm_r entry if File.executable? entry and Dir.reduced_entries(entry).size.eql? 0
                end
            end
        end


        def import_files directory, root
            Dir.each_status_and_entry(directory) do |status, entry|
                print status

                if File.directory? entry
                    Storage.import_files entry, root if File.executable? entry and not File.symlink? entry

                    FileUtils.rm_r entry if File.executable? entry and Dir.reduced_entries(entry).size.eql? 0
                elsif File.file? entry
                    hash = Storage.hash entry
                    name = Util.relative_path entry, root

                    Meta.create hash, name
                    Tag.create hash, name
                    Tag.create hash, 'taggutai/unmerged'

                    if Storage.has? hash
                        FileUtils.rm_f entry

                        puts " stored duplicated #{hash} (#{name})"
                    else
                        Storage.store hash, entry

                        puts " stored #{hash} (#{name})"
                    end
                end
            end
        end

        def import directory = IMPORT, root = directory
            if File.executable? directory
                import_symlinks directory, root
                delete_symlinks directory, root
                import_files directory, root

                Tag.find("taggutai/unmerged").each do |id|
                    Meta.merge id
                end
            end

            true

            unless File.executable? directory and Dir.reduced_entries(directory).size.eql? 0
                puts ' Some files could not be imported'

                false
            end
        end

        def has? id
            File.exists? "#{STORAGE}/#{id[0...40]}"
        end

        def store id, path
            raise DuplicateFileException if Storage.has? id

            if File.writable? path
                File.rename path, "#{STORAGE}/#{id[0...40]}"
            elsif File.readable? path
                FileUtils.cp path, "#{STORAGE}/#{id[0...40]}"
                FileUtils.rm_f path
            else
                raise Exception
            end

            Tag.create id[0...40], 'taggutai/untagged'
        end
    end
end

class Meta
    class << self
        def has? id
            result = true
            result = false unless Dir.exists? "#{TRACKING}/#{id[0...40]}"
            result = false unless File.exists? "#{TRACKING}/#{id[0...40]}/names"
            result

        end

        def create id, filename
            dirname = id[0...40]
            basename = 'names'

            FileUtils.mkdir_p "#{TRACKING}/#{dirname}" unless Dir.exists? "#{TRACKING}/#{dirname}"

            file = File.open "#{TRACKING}/#{dirname}/#{basename}", 'ab'
            file.puts filename
            file.close
        end

        def merge id
            [ 'names', 'tags' ].each do |group|
                items = File.readlines "#{TRACKING}/#{id[0...40]}/#{group}"

                File.write "#{TRACKING}/#{id[0...40]}/#{group}", items.sort.uniq.join
            end

            Tag.delete id, 'taggutai/unmerged'
        end
    end
end

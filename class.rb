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

        def create id, tag
            FileUtils.mkdir_p "#{TAGS}/#{tag}"
            FileUtils.touch "#{TAGS}/#{tag}/#{id[0...40]}"
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

            hash.hexdigest
        end

        def import_symlinks directory, root
            entries = Dir.entries(directory, { :encoding => 'utf-8' })
            total = entries.size - 2
            index = 0

            entries.each do |entry|
                next if [ '..', '.' ].include? entry

                index += 1
                entry = "#{directory}/#{entry}"

                printf "(%#{total.to_s.size}d/%d) ", index, total

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

                    Tag.create Storage.hash(sym), entry if File.exists? sym

                    puts "folllowed symlink (#{Util.relative_path entry, root})"
                end
            end
        end

        def delete_symlinks directory, root
            Dir.entries(directory, { :encoding => 'utf-8' }).each do |entry|
                next if [ '..', '.' ].include? entry

                entry = "#{directory}/#{entry}"

                if File.symlink? entry
                    FileUtils.rm_f entry
                elsif File.directory? entry
                    Storage.delete_symlinks entry, root if File.executable?

                    FileUtils.rm_r entry if (Dir.entries(entry, { :encoding => 'utf-8' }) - [ '..', '.' ]).size.eql? 0
                end
            end
        end


        def import_files directory, root
            entries = Dir.entries(directory, { :encoding => 'utf-8' })
            total = entries.size - 2
            index = 0

            entries.each do |entry|
                next if [ '..', '.' ].include? entry

                index += 1
                entry = "#{directory}/#{entry}"

                printf "(%#{total.to_s.size}d/%d) ", index, total

                if File.directory? entry
                    Storage.import_files entry, root if File.executable? entry and not File.symlink? entry

                    FileUtils.rm_r entry if (Dir.entries(entry, { :encoding => 'utf-8' }) - [ '..', '.' ]).size.eql? 0
                elsif File.file? entry
                    hash = Storage.hash entry
                    name = Util.relative_path entry, root

                    Meta.create hash, name unless Meta.has? hash
                    Tag.create hash, name

                    if Storage.has? hash
                        FileUtils.rm_f entry

                        puts "stored duplicated #{hash} (#{name})"
                    else
                        Storage.store hash, entry

                        puts "stored #{hash} (#{name})"
                    end
                end
            end
        end

        def import directory = IMPORT, root = directory
            import_symlinks directory, root
            delete_symlinks directory, root
            import_files directory, root
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

            FileUtils.touch "#{TAGS}/untagged/#{id[0...40]}"
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

            raise DuplicateFileException if Meta.has? id

            file = File.open "#{TRACKING}/#{dirname}/#{basename}", 'ab'
            file.puts filename
            file.close
        end
    end
end

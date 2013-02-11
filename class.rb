#!/usr/bin/env ruby
# coding: utf-8

require 'yaml'
require 'digest/sha1'
require 'fileutils'

PWD = File.dirname File.realpath __FILE__

path = "#{PWD}/config.yml"

config = YAML::load_file path
config[:paths] = {} unless config[:paths]

working = (config['paths']['working'] or PWD)
working = "#{PWD}/#{working}" unless working.start_with? '/' or working[/^[A-Z]:/]

WORKING = working
STORAGE = "#{WORKING}/" + (config['paths']['storage'] or 'storage')
TAGS = "#{WORKING}/" + (config['paths']['tags'] or 'tags')
TRACKING = "#{WORKING}/" + (config['paths']['tracking'] or 'meta')
IMPORT = "#{WORKING}/" + (config['paths']['import'] or 'import')
OPTIONS = (config['options'] or {})

$DESTRUCTIVE = false

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

        def empty? path
            !Dir.enum_for(:foreach, path).any? do |entry|
                /\A\.\.?\z/ !~ entry
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

            if difference.eql? 0 and path[0].eql? root[0]
                '.'
            else
                path.shift difference
                path.join '/'
            end
        end
    end
end

class Tag
    class << self
        def getall directory = TAGS, recurse = true
            tags = []

            Dir.each_status_and_entry(directory) do |status, entry|
                if File.directory? entry
                    tags << Util.relative_path(entry, directory)

                    fixed = recurse ? Tag.getall(entry) : []

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
            FileUtils.rm_r "#{TAGS}/#{tag}" if Dir.empty? "#{TAGS}/#{tag}"
        end

        def list id
            tags = []

            if File.exists? "#{TRACKING}/#{id[0...40]}/tags"
                file = File.open "#{TRACKING}/#{id[0...40]}/tags", 'rb'

                file.lines.each do |line|
                    tags << line.chomp
                end

                file.close
            end

            tags
        end

        def find tag
            files = []

            Dir.each_status_and_entry("#{TAGS}/#{tag}") do |status, entry|
                files << File.basename(entry) if File.file? entry
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
                        Tag.create Storage.hash(sym), 'taggutai/unmerged'
                    end

                    puts " folllowed symlink (#{entry})"
                end
            end
        end

        def delete_symlinks directory, root
            return unless $DESTRUCTIVE

            Dir.each_status_and_entry(directory) do |status, entry|
                if File.symlink? entry
                    FileUtils.rm_f entry
                elsif File.directory? entry
                    Storage.delete_symlinks entry, root if File.executable? entry

                    FileUtils.rm_r entry if File.executable? entry and Dir.empty? entry
                end
            end
        end


        def import_files directory, root
            Dir.each_status_and_entry(directory) do |status, entry|
                print status

                next if File.symlink? entry

                if File.file? entry
                    hash = Storage.hash entry
                    name = Util.relative_path entry, root

                    Meta.create hash, name
                    Tag.create hash, 'taggutai/unmerged'

                    if Storage.has? hash
                        FileUtils.rm_f entry if $DESTRUCTIVE

                        puts " stored duplicated #{hash} (#{name})"
                    else
                        Storage.store hash, entry

                        puts " stored #{hash} (#{name})"
                    end
                elsif File.directory? entry
                    Storage.import_files entry, root if File.executable? entry and not File.symlink? entry

                    FileUtils.rm_r entry if $DESTRUCTIVE and File.executable? entry and Dir.empty? entry
                end
            end
        end

        def import directory = IMPORT, root = directory
            $DESTRUCTIVE = File.realpath(directory).eql?(IMPORT) ? true : false

            if File.executable? directory
                import_symlinks directory, root
                delete_symlinks directory, root
                import_files directory, root

                Tag.find("taggutai/unmerged").each do |id|
                    Meta.merge id
                end
            end

            true

            unless (File.executable? directory and Dir.empty? directory) or not $DESTRUCTIVE
                puts ' Some files could not be imported'

                false
            end
        end

        def has? id
            File.exists? "#{STORAGE}/#{id[0...40]}"
        end

        def store id, path
            raise DuplicateFileException if Storage.has? id

            if File.writable? path and $DESTRUCTIVE
                FileUtils.mv path, "#{STORAGE}/#{id[0...40]}"
            elsif File.readable? path
                FileUtils.cp path, "#{STORAGE}/#{id[0...40]}"
                FileUtils.rm_f path if $DESTRUCTIVE
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

        def names id
            names = []
            file = File.open "#{TRACKING}/#{id[0...40]}/names", 'rb'

            file.lines.each do |line|
                names << line.chomp
            end

            file.close

            names
        end
    end
end

if __FILE__.eql? $0
    case ARGV[0]
    when 'import'
        if ARGV[1]
            unless Dir.exists? ARGV[1]
                $stderr.puts 'not a valid directory to import'

                exit 1
            end

            Storage.import ARGV[1]
        else
            Storage.import
        end
    when 'find'
        unless ARGV[1] and File.exists? ARGV[1] and File.file? ARGV[1]
            $stderr.puts 'please specify a file to search for in storage'

            exit 1
        end

        hash = Storage.hash ARGV[1]

        if Storage.has? hash

            tags = Tag.list hash

            $stderr.puts 'file exists in storage but there are no associated tags' if tags.eql? 0

            tags.each do |tag|
                puts tag
            end
        else
            $stderr.puts 'file does not exist in storage'

            exit 1
        end
    when 'hash'
        unless ARGV[1] and File.exists? ARGV[1] and File.file? ARGV[1]
            $stderr.puts 'please specify a file to hash'

            exit 1
        end

        puts Storage.hash ARGV[1]
    when 'tag'
        quit = false

        until quit
            puts "*** commands ***"
            puts '  1: add      2: delete'
            puts '  3: quit     4: list'
            puts '  5: untagged 6: find'
            print 'what now> '
            line = $stdin.gets.chomp

            case line
            when /^(3|q)$/
                quit = true
            when /^(4|l)$/
                tags = Tag.getall TAGS, false
                back = false
                root = TAGS

                until back
                    index = 0

                    puts "/#{Util.clean_path Util.relative_path root, TAGS}"

                    tags.each do |tag|
                        puts "  #{"%#{tags.size.to_s.size}d" % index += 1}: #{tag}"
                    end

                    if tags.size.eql? 0
                        puts '  no sub-tags'

                        root = root[0...root.rindex('/')]
                        tags = Tag.getall root, false

                        next
                    else
                        print 'list> '
                        line = $stdin.gets.chomp
                    end

                    case line
                    when /^(\d+)$/
                        index = $1.to_i - 1

                        if index < tags.size
                            root = "#{root}/#{tags[index]}"
                            tags = Tag.getall root, false
                        end
                    when ''
                        back = true if root.eql? TAGS

                        root = root[0...root.rindex('/')]
                        tags = Tag.getall root, false
                    else
                    end
                end
            when /^(5|u)$/
                files = Tag.find 'taggutai/untagged'
                current = 0

                p Meta.names files[current]
            when /^(6|f)$/
                tags = Tag.getall TAGS, false
                back = false
                string = ''

                until back
                    print 'find> '
                    string = $stdin.gets.chomp
                    set = tags

                    if string.start_with? '/'
                        content = true
                        string = string[1..-1]

                        if string.start_with? '?'
                            filetype = true
                            string = string[1..-1]
                        else
                            filetype = false
                        end
                    else
                        content = false
                    end

                    while string.include? '/'
                        limit = Tag.limit set, "#{string[0...string.index('/')]}.*"
                        string = string[string.index('/')+1..-1]
                        string = '.*' if string.empty?
                        sub = []

                        limit.each do |tag|
                            Tag.getall("#{TAGS}/#{tag}", false).each do |found|
                                sub << "#{tag}/#{found}"
                            end
                        end

                        set = sub.flatten
                    end

                    if string.empty?
                        back = true

                        next
                    end

                    limit = Tag.limit set, /#{string}.*$/

                    unless content
                        limit.each do |tag|
                            puts "  #{tag}"
                        end
                    else
                        limit.each do |tag|
                            Tag.find(tag).each do |file|
                                if filetype
                                    print "#{file} "
                                    puts %x[file -bi #{STORAGE}/#{file}]
                                else
                                    puts file
                                end
                            end
                        end
                    end
                end
            else
                puts "huh (#{line})?"
            end
        end
    else
        puts "taggutai import [<directory>]"
        puts "taggutai find <file>"
        puts "taggutai hash <file>"
    end
end

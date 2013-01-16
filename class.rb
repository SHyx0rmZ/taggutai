#!/usr/bin/env ruby
# coding: utf-8

require "yaml"

config = YAML::load_file "config.yml"
config[:paths] = {} unless config[:paths]

STORAGE = config["paths"]["storage"] or "storage"
TAGS = config["paths"]["tags"] or "tags"
TRACKING = config["paths"]["tracking"] or "meta"

class Util
    class << self
        def clean_path path
            array = path.kind_of? Array

            path = path.split "/" unless array

            clean = []

            path.each do |directory|
                case directory
                when ".."
                    clean.delete_at clean.size - 1
                when "."
                else
                    clean << directory
                end
            end

            clean = clean.join "/" unless array

            clean
        end
    end
end

class Tag
    class << self
        def getall directory
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

            tags
        end
    end
end

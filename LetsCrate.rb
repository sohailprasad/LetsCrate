#! /usr/bin/env ruby

# LetsCrate CLI by Freddy Roman

# ------

# Copyright (c) 2011 Freddy Roman
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#    
#     The above copyright notice and this permission notice shall be included in
#     all copies or substantial portions of the Software.
#     
#     THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
#     IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
#     FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
#     AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
#     LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
#     OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
#     THE SOFTWARE.

# ------

require 'rubygems'
require 'optparse'
require 'ostruct'
require 'typhoeus'
require 'json'

VERSION = "1.4.5"
APIVERSION = "1"
BaseURL = "https://api.letscrate.com/1/"

# here start the modules

module Colors      # this allows using colors with ANSI escape codes
    
    def colorize(text, color_code)
        "\e[#{color_code}m#{text}\e[0m"
    end
    
    def red(text); colorize(text, 31); end
    def green(text); colorize(text, 32); end
    def yellow(text); colorize(text, 33); end
    def blue(text); colorize(text, 34); end
    def magenta(text); colorize(text, 35); end
    def cyan(text); colorize(text, 36); end
    def white(text); colorize(text, 37); end
end

module Output
    
    def detect_terminal_size
        return `tput cols`.to_i    # returns terminal width in characters
    end
    
    def printError(message, argument)
        if !(@options.width.nil?)
            $stderr.puts red("Error:")+" #{message}%#{@options.width-(message.length+7)}s" % "<#{argument}>"
            else
            $stderr.puts red("Error:")+" #{message}\t<#{argument}>"
        end
    end
    
    def printInfo(name, short_code, id)
        name = truncateName(name, @options.width-35) if name.length > @options.width-35
        if !(@options.width.nil?)
            echo "#{name}%#{@options.width-(name.length)}s\n" % "URL: http://lts.cr/#{short_code}  ID: #{id}"   # this works by getting the remaining available characters and using %-#s to align to the right.
            else
            echo "#{name}\t\tURL: http://lts.cr/#{short_code}\tID: #{id}"  # in case that the terminal width couldn't be obtained.
        end
    end
    
    def printFile(name, short_code, id)
        name = truncateName(name, @options.width-37) if name.length > @options.width-37
        if !(@options.width.nil?)
            echo "* #{name}%#{@options.width-(name.length+2)}s\n" % "URL: http://lts.cr/#{short_code}  ID: #{id}"
            else
            echo "* #{name}\t\tURL: http://lts.cr/#{short_code}\tID: #{id}"
        end
    end
    
    def truncateName(name, length)
        return name[0..((length/2)-2).truncate]+"..."+name[-(((length/2)-1).truncate)..-1]
    end
    
    def echo(argument)    #  this behaves exactly like puts, unless quiet is on. Use for all output messages.
        puts argument unless @options.quiet
    end
    
end

module IntegrityChecks
    
    def IDvalid?(id)
        test = id.to_s
        if test[/^\d{5}$/].nil?  # regex checks for 5 continuous digits surrounded by start and end of string.
            return false
        else
            return true
        end
    end
    
    def IDsvalid?(ids)
        results = []
        
        for id in ids
            results << IDvalid?(id)
        end
        
        unless results.include?(false)
            return true
        else
            return false
        end
    end
    
end

module Strings   # this module contains almost all the strings used in the program
    
    STR_BANNER = "Usage: #{File.basename(__FILE__)} <-l username:password> [options] file1 file2 ...\n"+ 
    "   or: #{File.basename(__FILE__)} <-l username:password> [options] name1 name2 ..."
    
    STR_VERSION = "LetsCrate v#{VERSION} (API Version #{APIVERSION}) by Freddy Roman <frcepeda@gmail.com>"
    
    STR_TOO_MANY_ACTIONS = "More than one action was selected. Please select only one action."
    
    STR_FILEID_ERROR = "A file ID is a 5 digit number. Use -a to list your files's IDs."
    STR_CRATEID_ERROR = "A crate ID is a 5 digit number. Use -A to list your crates's IDs."
    
    STR_RTFM = "Use the -h flag for help, or read the README."
    
    STR_ACCOUNT_NEEDED = "You need to an account to use the LetsCrate API."
    STR_LOGIN_WITH_L_SWITCH = "Use the \"-l\" switch to specify your login credentials"
    STR_CREDENTIALS_ERROR = "Credentials invalid, please input them in the format \"username:password\""
    
    STR_VALID_CREDENTIALS = "The credentials are valid"
    STR_INVALID_CREDENTIALS = "The credentials are invalid"
    
    STR_EMPTY_CRATE = "* Crate is empty."

    STR_NO_FILES_FOUND = "No files were found that match that name."
    STR_NO_CRATES_FOUND = "No crates were found that match that name."
    
    STR_TOO_MANY_CRATES = "More than 1 crate matched that name. Please make your query more specific."
    STR_TOO_MANY_FILES = "More than 1 file matched that name. Please make your query more specific."
    
    STR_DELETED = "%s deleted"
    STR_RENAMED = "Renamed %s to %s"
end

module Everything    # I got tired of manually adding all modules.
    include Colors
    include Output
    include IntegrityChecks
    include Strings
end

#  here end the modules

class App
    
    include Everything
    
    def initialize(argList)
        @arguments = argList      # store arguments in local variable
        processArguments
    end
    
    def processArguments
        
        @options = OpenStruct.new    # all the arguments will be parsed into this openstruct
        @options.actionCounter = 0     # this should always end up as 1, or else there's a problem with the script arguments.
        @options.action = nil    # this will be performed by the LetsCrate class
        @options.quiet = false    # if true, nothing will be printed to the screen. (aside from errors)
        @options.width = detect_terminal_size   # determine terminal's width
        @options.usesFilesIDs = false    # this triggers ID checks on the arguments if set to true
        @options.usesCratesIDs = false   # same as above but with crates
        @options.regex = false    # if set to true, all names are treated as regular expressions
        
        opts = OptionParser.new
        
        opts.banner = STR_BANNER
        
        opts.separator ""
        opts.separator "Mandatory arguments:"
        
        opts.on( '-l', '--login [username:password]', 'Login with this username and password' ) { |login|
            
            credentials = login.split(/:/)   # makes a 2-item array from the input
            
            if credentials.count == 2   # this array musn't have more than 2 items because it's username + password.
                @options.username = credentials[0]
                @options.password = credentials[1]
                @options.login = 1
            else
                printError(STR_CREDENTIALS_ERROR, login.to_s)
                exit 1
            end
        }
        
        opts.separator ""
        opts.separator "File functions:"
        
        opts.on( '-u', '--upload [Crate name]', 'Upload files to crate' ) { |upID|
            @options.crateID = upID
            @options.action = :uploadFile
            @options.actionCounter += 1
        }
        
        opts.on( '-d', '--delete', 'Delete files with names *' ) {
            @options.action = :deleteFile
            @options.usesFilesIDs = true
            @options.actionCounter += 1
        }
        
        opts.on( '-a', '--list', 'List all files' ) {
            @options.action = :listFiles
            @options.actionCounter += 1
        }
        
        opts.on( '-s', '--search', 'Search for files with names' ) {
            @options.action = :searchFile
            @options.actionCounter += 1
        }
        
        opts.on( '-i', '--id', 'Show files with IDs' ) {
            @options.action = :listFileID
            #this should have a @options.usesFilesIDs = true, but the command is meaningless without an ID
            @options.actionCounter += 1
        }
        
        opts.separator ""
        opts.separator "Crate functions:"
        
        opts.on( '-N', '--newcrate', 'Create new crates with names' ) {
            @options.action = :createCrate
            @options.actionCounter += 1
        }
        
        opts.on( '-A', '--listcrates', 'List all crates (or files in crates, if names are passed)' ) {
            @options.action = :listCrates
            @options.actionCounter += 1
        }
        
        opts.on( '-S', '--searchcrates', 'Search for crates with names' ) {
            @options.action = :searchCrate
            @options.actionCounter += 1
        }
        
        opts.on( '-R', '--renamecrate [Crate name]', 'Rename crate to name' ) { |crateID|
            @options.crateID = crateID
            @options.action = :renameCrate
            @options.actionCounter += 1
        }
        
        opts.on( '-D', '--deletecrate', 'Delete crates with names *' ) {
            @options.action = :deleteCrate
            @options.usesCratesIDs = true
            @options.actionCounter += 1
        }
        
        opts.separator ""
        opts.separator "Misc. options:"
        
        opts.on( '-r', '--regexp', 'Treat all names as regular expressions' ) {
            @options.regex = true
        }
        
        opts.on( '-t', '--test', 'Only test the credentials' ) {
            @options.action = :testCredentials
            @options.actionCounter += 1
        }
        
        opts.on( '-q', '--quiet', 'Treat all names as regular expressions' ) {
            @options.quiet = true
        }
        
        opts.on( '-v', '--version', 'Output version' ) {
            puts STR_VERSION
            exit 0
        }
        
        opts.on( '-h', '--help', 'Display this screen' ) {
            puts opts   # displays help screen
            exit 0
        }
        
        opts.parse!(@arguments)
        
        # Errors:
        
        if @options.actionCounter > 1
            printError(STR_TOO_MANY_ACTIONS, "#{@options.actionCounter}")
            $stderr.puts STR_RTFM
            exit 1
        end
        
        if (@options.username == nil || @options.password == nil) && @options.actionCounter != 0
            printError(STR_ACCOUNT_NEEDED, "NoLoginError")
            $stderr.puts STR_LOGIN_WITH_L_SWITCH
            exit 1
        end
        
        if @options.actionCounter == 0      # nothing was selected
            puts opts
            exit 0
        end
    end
    
    def run
        
        crate = LetsCrate.new(@options, @arguments)
        crate.run
        
    end
    
end

class LetsCrate
    
    include Everything
    
    def initialize(options, arguments)
        @options = options
        @arguments = arguments
        @argCounter = -1    # argument index is raised first thing on every method, and it needs to be 0 the first time it's used.
        @prevNames = []   # used when renaming or deleting stuff.
    end
    
    def run
        
        if !(@options.crateID.nil?)    #  Check if crateID is used in this process.
            if IDvalid?(@options.crateID)
                # YAY! Do nothing.
            else
                @options.crateID = getIDForCrate(@options.crateID)
            end
        end
        
        if @options.usesCratesIDs
            
            if IDsvalid?(@arguments)   #  that means I have to parse all the arguments.
                # YAY! Do nothing.
            else
                if @options.regex
                    @arguments = getIDsForCrates!(@arguments)
                else
                    @arguments = getIDsForCrates(@arguments)
                end
            end
        end
        
        if @options.usesFilesIDs
            
            if IDsvalid?(@arguments)   #  that means I have to parse all the arguments.
                # YAY! Do nothing.
            else
                if @options.regex
                    @arguments = getIDsForFiles!(@arguments)
                else
                    @arguments = getIDsForFiles(@arguments)
                end
            end
        end
        
        if @arguments.count > 0     # check if command requires extra arguments
            
            for argument in @arguments
                response = self.send(@options.action, argument)    # response is a parsed hash or an array of hashes.
                self.send("PRINT"+@options.action.to_s, response)
            end
        else
            response = self.send(@options.action)    # response is a parsed hash or an array of hashes.
            self.send("PRINT"+@options.action.to_s, response)
        end
    end
    
    # -----   API documentation is at http://letscrate.com/api
    
    def testCredentials
        response = Typhoeus::Request.post("#{BaseURL}users/authenticate.json",
                                          :username => @options.username,
                                          :password => @options.password,
                                          )
        
        return parseResponse(response)
    end
    
    def uploadFile(file)
        if IDvalid?(@options.crateID)
            response = Typhoeus::Request.post("#{BaseURL}files/upload.json",
                                          :params => {
                                            :file => File.open(file ,"r"),
                                            :crate_id => @options.crateID
                                          },
                                          :username => @options.username,
                                          :password => @options.password,
                                          )
        
            return parseResponse(response)
        else
            printError(STR_CRATEID_ERROR, @options.crateID)
            exit 1
        end
    end
    
    def deleteFile(fileID)
        if IDvalid?(fileID)
            @prevNames << getFileName(fileID)
            response = Typhoeus::Request.post("#{BaseURL}files/destroy/#{fileID}.json",
                                                :username => @options.username,
                                                :password => @options.password,
                                                )
            
            return parseResponse(response)
        else
            printError(STR_FILEID_ERROR, fileID)
        end
    end
    
    def listFiles
        response = Typhoeus::Request.post("#{BaseURL}files/list.json",
                                                 :username => @options.username,
                                                 :password => @options.password,
                                                 )
        
        return parseResponse(response)
    end
    
    def listFileID(fileID)
        if IDvalid?(fileID)
            response = Typhoeus::Request.post("#{BaseURL}files/show/#{fileID}.json",
                                                 :username => @options.username,
                                                 :password => @options.password,
                                                 )
        
            return parseResponse(response)
        else
            printError(STR_FILEID_ERROR, fileID)
        end
            
    end
    
    def searchFile(name)
        regex = Regexp.new(name, Regexp::IGNORECASE)   # make regex class with every argument
        matchedFiles = []
        @files = listFiles if @files.nil?   # do not query the server each time a search is made.
        allCrates = @files['crates']
        for crate in allCrates
            if crate['files']      # test if crate is empty
                for file in crate['files']
                    matchedFiles << file if regex.match(file['name']) != nil
                end
            end
        end
        return matchedFiles
    end
    
    def searchCrate(name)
        regex = Regexp.new(name, Regexp::IGNORECASE)   # make regex class with every argument
        matchedCrates = []
        @files = listFiles if @files.nil?   # do not query the server each time a search is made.
        allCrates = @files['crates']
        for crate in allCrates
            matchedCrates << crate if regex.match(crate['name']) != nil
        end
        return matchedCrates
    end
    
    def createCrate(name)
        response = Typhoeus::Request.post("#{BaseURL}crates/add.json",
                                                 :params => {
                                                 :name => name
                                                 },
                                                 :username => @options.username,
                                                 :password => @options.password,
                                                 )
       
        return parseResponse(response)
    end
    
    def listCrates(*name)
        if name.count == 0   # was I passed a name?
            response = Typhoeus::Request.post("#{BaseURL}crates/list.json",
                                             :username => @options.username,
                                             :password => @options.password,
                                             )
            return parseResponse(response)
        else  # that means i have to parse it.
            crates = searchCrate(name[0]) # I need to pass the name like that because Ruby groups all variable number arguments into an array.
            hash = {"crates" => crates}  # PRINTlistFiles expects the original response from the server. This mimics the format of the hash.
            PRINTlistFiles(hash)
            return nil    # don't return anything. I already outputed everything to the terminal.
        end
    end
    
    def renameCrate(name)
        if IDvalid?(@options.crateID)
            @prevNames << getCrateName(@options.crateID)
            response = Typhoeus::Request.post("#{BaseURL}crates/rename/#{@options.crateID}.json", # the crateID isn't an argument, the name is.
                                                 :params => {
                                                 :name => name
                                                 },
                                                 :username => @options.username,
                                                 :password => @options.password,
                                                 )
        
            return parseResponse(response)
        else
            printError(STR_CRATEID_ERROR, @options.crateID)
            exit 1
        end
    end
    
    def deleteCrate(crateID)
        if IDvalid?(crateID)
            @prevNames << getCrateName(crateID)
            response = Typhoeus::Request.post("#{BaseURL}crates/destroy/#{crateID}.json",
                                                 :username => @options.username,
                                                 :password => @options.password,
                                                 )
      
            return parseResponse(response)
        else
            printError(STR_CRATEID_ERROR, crateID)
        end
    end
    
    # ------
    
    def parseResponse(response)
        return JSON.parse(response.body)
    end
    
    # ------
    
    def PRINTtestCredentials(hash)
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("success")
            echo STR_VALID_CREDENTIALS
            else
            printError(STR_INVALID_CREDENTIALS, "User:#{@options.username} Pass:#{@options.password}")
        end
    end
    
    def PRINTuploadFile(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            printInfo(File.basename(@arguments[@argCounter]), hash['file']['short_code'], hash['file']['id'])
        end
    end
    
    def PRINTdeleteFile(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            echo STR_DELETED % [@prevNames[@argCounter]]
        end
    end
    
    def PRINTlistFiles(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
                printError(hash['message'], @arguments[@argCounter])
        else
            crates = hash['crates']
            for crate in crates
                echo "\n"
                printInfo(crate['name'], crate['short_code'], crate['id'])
                if crate['files']      # test if crate is empty
                    for file in crate['files']
                        printFile(file['name'], file['short_code'], file['id'])
                    end
                else
                    echo STR_EMPTY_CRATE
                end
            end
        end
    end
        
    def PRINTsearchFile(array)
        @argCounter += 1
        if array.empty?
            printError(STR_NO_FILES_FOUND, @arguments[@argCounter])
        else
            echo "\n"
            echo green(@arguments[@argCounter]+":")  # print header for matched files
            for file in array
                printInfo(file['name'], file['short_code'], file['id'])
            end
        end
    end
    
    def PRINTsearchCrate(array)
        @argCounter += 1
        if array.empty?
            printError(STR_NO_CRATES_FOUND, @arguments[@argCounter])
        else
            echo "\n"
            echo green(@arguments[@argCounter]+":")   # print header for matched files
            for crate in array
                printInfo(crate['name'], crate['short_code'], crate['id'])
            end
        end
    end
    
    def PRINTlistFileID(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            printInfo(hash['item']['name'], hash['item']['short_code'], hash['item']['id'])
        end
    end
    
    def PRINTcreateCrate(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            printInfo(hash['crate']['name'], hash['crate']['short_code'], hash['crate']['id'])
        end
    end
    
    def PRINTlistCrates(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            crates = hash['crates']
            for crate in crates
                printInfo(crate['name'], crate['short_code'], crate['id'])
            end
        end
    end
    
    def PRINTrenameCrate(hash)
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            echo STR_RENAMED % [@prevNames[0], hash['crate']['name']]   # using 0 as magic number because this always uses only one argument.
        end
    end
    
    def PRINTdeleteCrate(hash)
        @argCounter += 1
        return 0 if hash.nil?    # skip the output if hash doesn't exist.
        if hash.values.include?("failure")
            printError(hash['message'], @arguments[@argCounter])
        else
            echo STR_DELETED % [@prevNames[@argCounter]]
        end
    end
    
    # Map names to IDs
    
    def getIDsForCrates(array)
        ids = []
        for name in array
            next if IDvalid?(name)
            crates = searchCrate(name) if @crates.nil?
            for crate in crates
                ids << crate['id'].to_s
            end
        end
        
        if ids.count == array.count
            return ids
        elsif ids.count == 0
            printError(STR_NO_CRATES_FOUND, name)
            exit 1
        elsif ids.count > array.count
            printError(STR_TOO_MANY_CRATES, name)
            exit 1
        end
    end
    
    def getIDsForFiles(array)
        ids = []
        for name in array
            next if IDvalid?(name)
            files = searchFile(name)
            for file in files
                ids << file['id'].to_s
            end
        end
        
        if ids.count == array.count
            return ids
        elsif ids.count == 0
            printError(STR_NO_FILES_FOUND, name)
            exit 1
        elsif ids.count > array.count
            printError(STR_TOO_MANY_FILES, name)
            exit 1
        end
    end
    
    def getIDsForCrates!(array)  # these methods return ALL the matches for all the IDs. Used with --regexp
        ids = []
        for name in array
            next if IDvalid?(name)
            crates = searchCrate(name) if @crates.nil?
            for crate in crates
                ids << crate['id'].to_s
            end
        end
        return ids
    end
    
    def getIDsForFiles!(array)  # these methods return ALL the matches for all the IDs. Used with --regexp
        ids = []
        for name in array
            next if IDvalid?(name)
            files = searchFile(name)
            for file in files
                ids << file['id'].to_s
            end
        end
        return ids
    end
    
    def getIDForCrate(name)
        id = getIDsForCrates([name])
        if id.count == 1
            return id[0]
        elsif id.count == 0
            printError(STR_NO_CRATES_FOUND, name)
            exit 1
        elsif id.count > 1
            printError(STR_TOO_MANY_CRATES, name)
            exit 1
        end
    end
    
    def getIDForFile(name)
        id = getIDsForFiles([name])
        if id.count == 1
            return id[0]
        elsif id.count == 0
            printError(STR_NO_FILES_FOUND, name)
            exit 1
        elsif id.count > 1
            printError(STR_TOO_MANY_FILES, name)
            exit 1
        end
    end
    
    # map IDs to names.
    
    def getCrateName(id)
        @files = listFiles if @files.nil?   # do not query the server each time a search is made.
        regex = Regexp.new(id.to_s, Regexp::IGNORECASE)
        allCrates = @files['crates']
        for crate in allCrates
            match = crate if regex.match(crate['id'].to_s) != nil
        end
        return match['name']
    end
    
    def getFileName(id)
        @files = listFiles if @files.nil?   # do not query the server each time a search is made.
        regex = Regexp.new(id.to_s, Regexp::IGNORECASE)
        allCrates = @files['crates']
        for crate in allCrates
            if crate['files']      # test if crate is empty
                for file in crate['files']
                    match = file if regex.match(file['id'].to_s) != nil
                end
            end
        end
        return match['name']
    end
end

# Create and run the application
app = App.new(ARGV)
app.run
exit 0
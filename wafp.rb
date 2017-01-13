#!/usr/bin/ruby
################################################################################
# WAFP - Web Application Finger Printer
################################################################################
# 0.01-26c3 - 2009.12.28 - by Richard Sammet (e-axe) richard.sammet@gmail.com
################################################################################
# inspired by: 
#   "http://sucuri.net/?page=docs&title=webapp-version-detection"
################################################################################
# Information and latest version available at:
# http://mytty.org/wafp/
################################################################################
# This file is part of WAFP.
#
# WAFP is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# WAFP is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with WAFP; if not, write to the Free Software Foundation,
# Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301  USA
#
# http://www.gnu.org/licenses/gpl.txt
################################################################################
# KNOWN BUGS:
# ruby reports a deadlock -> http://redmine.ruby-lang.org/issues/show/1471
#   - looks like this is ruby version dependant (occurred with 1.8.6)
# TODO:
# finish proxy support
################################################################################

# the lib requirements

begin
  # this is required for all the people using rubygems on their systems
  require 'rubygems'
rescue LoadError
end
require 'getoptlong'
begin
  require 'sqlite3'
rescue LoadError
  puts "ERROR: please install sqlite3 for ruby!"
  exit 0 
end
# this is a modified version of net/http
require "lib/wafp_http.rb"
require "lib/wafp_https.rb"
# this is a modified version of pidify
require "lib/wafp_pidify.rb"
require 'uri'
require 'thread'
require 'timeout'
require 'digest/md5'

# some constants
CODENAME     = 'WAFP';
WAFPVERSION  = '0.01-26c3';
AUTHOR       = 'Richard Sammet (e-axe)';
CONTACT      = 'richard.sammet@gmail.com';
WEBSITE      = 'http://mytty.org/wafp/';
# the databases
FDB          = 'fprints_wafp.db'
SDB          = 'scan_wafp.db'
# predefined http headers
USERAGENT    = 'Mozilla/5.0 (X11; U; Linux i686; en-US; rv:1.9.0.10) Gecko/2009050223 Gentoo Firefox/3.0.10'

# check if wafp is already running
if Pidify.running? or Pidify.pid_exists? then
  puts "ERROR: #{$0} is already running!"
  puts "ERROR: If it is not, you can remove the PID file (#{Pidify.pid_file}) by hand."
  puts "ERROR: PLEASE DO NOT START WAFP MULTIPLE TIMES WITH THE SAME DB ON THE SAME MACHINE!"
  exit 0
else
  Pidify.start
end

# globals
@db = nil
@memdb = nil
@lowmem = false
@verbose = false
@debug = false
@quiet = false
@idcount = 10
@tstamp = Time.now.to_i
@scanid = "#{$$}#{@tstamp}"
@cancel_info = Array.new()
# you can add all the header fields you want right here...
@headers = {
              'User-Agent' => USERAGENT,
              #'X-Testme'   => "VOID"
           }

# trapping the INT signal, cleaning up and exit
trap("INT") do
  tries = 0
  puts "received sig-int ... cleaning up." if !@quiet
  # well, lets just close the db if its open and open it again for the cleaning
  begin
    tries = tries + 1
    dbclose(@db)
  rescue
    if tries > 25 then
      puts "ERROR: We were not able to clean the database! Exiting anyways!"
      Pidify.stop
      exit(-1)
    end
    sleep 0.1
    retry
  end
  if @cancel_info[1] == nil then
    @db = dbopen(SDB)
    @db.execute( "DELETE FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{@cancel_info[0]}\" LIMIT 1)" )
    puts "DEBUG: executed SQL query: DELETE FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{@cancel_info[0]}\" LIMIT 1)" if @debug
    @db.execute( "DELETE FROM tbl_store WHERE name = \"#{@cancel_info[0]}\"" )
    puts "DEBUG: executed SQL query: DELETE FROM tbl_store WHERE name = \"#{@cancel_info[0]}\"" if @debug
    dbclose(@db)
    puts "VERBOSE: temp. scan data for scan \"#{@cancel_info[0]}\" deleted." if @verbose
  end

  Pidify.stop
  exit 0
end # trap()

# print the USAGE message and exit
def usage()

  puts "USAGE: #{$0} [Options] {URL}"
  puts "--"
  puts " -p, --product STRING       a string which represents the name of the product to check for;"
  puts "                            STRING can be something like: \"wordpress\""
  puts " -v, --pversion STRING      a string which represents the versions of the product to check for;"
  puts "                            STRING can be something like: \"2.2.1\" or \"%.2\" or \"1.%\"."
  puts " -P, --dump-products STRING this will dump all products for which fingerprints are available;"
  puts "                            STRING can be something like: \"%bb%\" which will select all products"
  puts "                            having bb|BB in their name."
  puts " -s, --store STRING         write the fetched data to the database for later use;"
  puts "                            STRING is used as an identifier."
  puts " -f, --fetch                fetch only - do not fingerprint the app."
  puts "                            (mostly used in conjunction with -s)"
  puts " -l, --list STRING          list the stored data archives containing STRING."
  puts "                            STRING is optional in this case."
  puts " -d, --dry STRING           perform the fingerprint on the stored data STRING instead of fetching it."
  puts " -t, --threads INT          this is the count of threads to use. [8]"
#  puts "     --proxy STRING         a STRING which holds the proxy information and optional"
#  puts "                            user/password combination;"
#  puts "                            e.g. http://user:pass@proxy.host.org:8080/"
#  puts "                            STRING can also be ENV - http_proxy environ variable."
  puts "     --user-agent STRING    a STRING which holds the User-Agent headerfield contents."
  puts "     --outlines INT         number of results to print. [10]"
  puts "     --timeout INT          connection timeout in seconds. [10]"
  puts "     --retries INT          maximum retries per file to fetch. [3]"
  puts "     --any                  this causes wafp to fetch all files known by fingerprints of all products."
  puts "     --low-mem              this causes wafp to NOT load the fingerprint database to the memory."
  puts "     --verbose              turns on verbose output."
  puts "     --debug                turns on debug output."
  puts "     --quiet                output off - besides the final results."
  puts "     --dbinfo               prints some database stats."
  puts "     --version              print WAFP version and exit."
  puts " -h, --help                 print this help and exit."
  puts ""
  puts "EXAMPLES:"
  puts " #{$0} -p 'wordpress' -v '2%' http://blog.example.com/"
  puts " #{$0} -f -t 32 -s phpmy-save01 -p 'phpmyadmin' -v '1.1.%' https://user:pass@www.example.com/phpmyadmin/"
  puts " #{$0} -d phpmy-save01 -p 'phpmyadmin' -v '1.1.%'"

  Pidify.stop
  exit 0

end # usage()

# print the version information and exit
def version()

  puts "version: \t#{WAFPVERSION}"
  puts "codename: \t#{CODENAME}"
  puts "author: \t#{AUTHOR}"
  puts "website: \t#{WEBSITE}"

  Pidify.stop
  exit 0

end # version()

# to make this a little shorter...
def dbopen(db)

  return @memdb if @lowmem == false and db == FDB and @memdb != nil

  return SQLite3::Database.new( db )

end # dbopen()

# to make this a little shorter...
def dbclose(db)

  return nil if @lowmem == false and db == @memdb

  db.close if !db.closed?

  return nil # well, you are welcome to add some error handling ;)

end # dbclose()

# loads a sqlite3 db into memory
def loadb(db)

  puts "VERBOSE: loading the fingerprint database to the ram..." if @verbose
  @memdb = SQLite3::Database.new( ":memory:" )
  qry = db.execute( "SELECT sql FROM sqlite_master WHERE sql NOT NULL" )
  @memdb.execute( "BEGIN" )
  qry.each do |l| 
    @memdb.execute( l.to_s.gsub(/\r?\n/, " ") )
  end
  @memdb.execute( "COMMIT" )

  @memdb.execute( "ATTACH DATABASE '#{FDB}' as fprintdb" )
  
  qry = @memdb.execute( "SELECT name FROM fprintdb.sqlite_master WHERE type='table'" )
  @memdb.execute( "BEGIN" )
  qry.each do |l| 
    @memdb.execute( "INSERT INTO main.#{l.to_s} SELECT * from fprintdb.#{l.to_s}" )
  end
  @memdb.execute( "COMMIT" )
  @memdb.execute( "DETACH DATABASE fprintdb" )
  
  dbclose(db)

  return @memdb

end # loadb()

# this func dumps the products and versions available in our database
# and yes, i know that this is not sql injection safe - wuuhhhaaaa hack yourself ;)
def dump(dproducts)

  @db = dbopen(FDB)
  products = @db.execute( "SELECT DISTINCT name FROM tbl_product WHERE name LIKE \"#{dproducts}\" ORDER BY name ASC" )
  puts "DEBUG: executed SQL query: SELECT DISTINCT name FROM tbl_product WHERE name LIKE \"#{dproducts}\" ORDER BY name ASC" if @debug
  
  products.each do |pname|
    cc = false # a little helper for a more sane output
    puts "#{pname}:"
    @db.execute( "SELECT DISTINCT versionstring FROM tbl_product WHERE name = \"#{pname}\" ORDER BY versionstring ASC" ) do |vstring|
      if cc == true then print ", " else cc = true end
      print "#{vstring}"
    end
    puts "DEBUG: executed SQL query: SELECT DISTINCT versionstring FROM tbl_product WHERE name = \"#{pname}\" ORDER BY versionstring ASC" if @debug
    puts ""
  end

  dbclose(@db)

  Pidify.stop
  exit 0

end # dump()

# just list the stored scans filtered by "list"
def liststore(list)

  @db = dbopen(SDB)
  scans = @db.execute( "SELECT DISTINCT name FROM tbl_store WHERE name LIKE \"#{list}\" ORDER BY name ASC" )
  puts "DEBUG: executed SQL query: SELECT DISTINCT name FROM tbl_store WHERE name LIKE \"#{list}\" ORDER BY name ASC" if @debug

  scans.each do |scan|
    puts scan
  end

  dbclose(@db)

  Pidify.stop
  exit 0

end # liststore()

# print some stats of our databases
def dbinfo()

  @db = dbopen(FDB)

  puts "_WAFP Database Stats_"
  pcnt = @db.execute( "SELECT DISTINCT name FROM tbl_product" )
  puts "DEBUG: executed SQL query: SELECT DISTINCT name FROM tbl_product" if @debug
  puts "Number of products: #{pcnt.length}"
  vcnt = @db.get_first_value( "SELECT count(versionstring) FROM tbl_product" )
  puts "DEBUG: executed SQL query: SELECT count(versionstring) FROM tbl_product" if @debug
  puts "Number of versions: #{vcnt}"
  fcnt = @db.get_first_value( "SELECT count(*) FROM tbl_fprint" )
  puts "DEBUG: executed SQL query: SELECT count(*) FROM tbl_fprint" if @debug
  puts "Number of fingerprint checks: #{fcnt}"

  dbclose(@db)
  @db = dbopen(SDB)

  scnt = @db.get_first_value( "SELECT count(*) FROM tbl_store" )
  puts "Number of stored scans: #{scnt}"
  fcnt = @db.get_first_value( "SELECT count(*) FROM tbl_results" )
  puts "Number of stored fingerprint checks: #{fcnt}"

  dbclose(@db)

  Pidify.stop
  exit 0

end # dbinfo()

def identify_product(uri, pproxy, threads, tout, rtry, save)

  paths = Hash.new
  products = Hash.new
  matches = Hash.new
  tmatches = Hash.new
  idproduct = nil
  idmatches = nil

  puts "Collecting and fetching the files we need to identify the product ..." if !@quiet

  @db = dbopen(FDB)

  products = @db.execute( "SELECT DISTINCT name FROM tbl_product" )
  products.each do |prod|
    paths[prod] = @db.execute( "SELECT DISTINCT path FROM tbl_fprint WHERE product_id IN(SELECT id FROM tbl_product WHERE name = \"#{prod}\") GROUP BY path ORDER BY count(path) DESC LIMIT #{@idcount}" )
  end

  dbclose(@db)

  paths.each do |prod, path|
    print "\nChecking for product: " + prod.to_s + "\n" if @verbose
    print "For paths: " + path.to_s + "\n" if @debug
    matches = check(scan_name = nil, product = prod.to_s, pversion = "%", idrun = true, fetch(path, uri, pproxy, threads, tout, rtry, nil, save))
    tmatches = tmatches.merge(matches)
  end

  tmatches = tmatches.sort {|a,b| -1*(a[1][2]<=>b[1][2]) }
  idproduct, idmatches = tmatches[0]
  products.each do |prod|
    if idproduct =~ /^#{prod}-/ and idmatches[2].to_f > 0.00 then
      printf(STDOUT, "\nIdentified Product: %s (%.2f %%)\n", prod, idmatches[2].to_f) if !@quiet
      return prod
    end
  end

  puts ""
  puts "WARNING: The auto product identification was not able to identify the product on the"
  puts "WARNING: targeted site. You can make use of the --any option or guess the product"
  puts "WARNING: yourself and add -p paramater."

  Pidify.stop
  exit 0

end # identify_product()

# select the files we need to fetch from the database
def tofetch(product, pversion)

  puts "Collecting the files we need to fetch ..." if !@quiet

  @db = dbopen(FDB)
  paths = @db.execute( "SELECT DISTINCT path FROM tbl_fprint WHERE product_id IN (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring LIKE \"#{pversion}\" ORDER BY name ASC) ORDER BY path ASC" )
  puts "DEBUG: executed SQL query: SELECT DISTINCT path FROM tbl_fprint WHERE product_id IN (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring LIKE \"#{pversion}\" ORDER BY name ASC) ORDER BY path ASC" if @debug

  dbclose(@db)

  if paths.length == 0 then
    puts "WARNING: There are not fingerprints matching your options!" if !@quiet
    Pidify.stop
    exit 0
  end

  paths

end # tofetch()

# this function generates the sorted result output
def genoutput(hashes, lines)

  n = 0

  matches = hashes[0]
  rcmatches = hashes[1]

  # sort the rc/matches hash by percentage of match
  matches = matches.sort {|a,b| -1*(a[1][2]<=>b[1][2]) }
  if rcmatches != nil then
    rcmatches = rcmatches.sort {|a,b| -1*(a[1]<=>b[1]) }
  end

  # printing the results
  puts "" if !@quiet
  puts  " found the following matches (limited to #{lines.to_i}):" if !@quiet
  print "+-------------------------------------------------------------+\n" if !@quiet
  matches.each do |pname,cntp|
    printf(STDOUT, " %-35s\t%4s / %-4s (%.2f%%)\n", pname, cntp[0], cntp[1], cntp[2].to_f)
    break if (n += 1) >= lines.to_i
  end
  print "+-------------------------------------------------------------+\n" if !@quiet
  puts  " #{CODENAME} #{WAFPVERSION}  - - - - - - - - -  #{WEBSITE}" if !@quiet

  if @verbose and rcmatches != nil then
    puts ""
    puts "VERBOSE: Returncode stats:"
    rcmatches.each do |key, val|
      puts "VERBOSE: Ret-Code\t#{key}\t##{val}"
    end
  end

end # genoutput()

# fetch required files multithreaded and store the
# paths, checksums and return codes inside the db
def fetch(paths, uri, pproxy, mthreads, tout, rtry, scan_name, save)

  @db = dbopen(SDB)
  ts = Array.new
  m = Mutex.new
  md5sums = Array.new
  threads = 0
  user = nil
  pass = nil
  puser = nil
  ppass = nil
  phost = nil
  pport = nil

  turi = URI.parse(uri)

  if turi.userinfo then
    user, pass = turi.userinfo.split(/:/)
    puts "detected username (#{user}) and password (#{"*" * pass.length}) for basic-auth." if @verbose
  end
  # TODO: the following proxy stuff gets not used yet
  if pproxy then
    phost = pproxy.host
    pport = pproxy.port
    puts "detected proxy host (#{phost}) and port (#{pport})." if @verbose
    if pproxy.userinfo then
      puser, ppass = pproxy.userinfo.split(/:/)
      puts "detected proxy username (#{puser}) and password (#{"*" * ppass.length}) for basic-auth." if @verbose
    end
  end

  if save then
    puts "Fetching needed files (##{paths.length}), calculating checksums and storing the results to the database:" if !@quiet
  elsif !save and @verbose then
    puts "Fetching needed files (##{paths.length}) and calculating checksums:" if !@quiet
  end

  paths.each do |path|
    if threads < mthreads then
      m.synchronize do
        threads += 1
        puts "VERBOSE: running with #{threads} threads!" if @debug
      end
      ts << Thread.new(path) do |path|
        res = nil
        req = nil
        rrtry = 0
        md5sum = nil
        path = path.to_s.gsub(/^\.\//, '/')
        # fetching the static files...
        begin
          Timeout::timeout(tout) do
            # TODO: add proxy support
            req = Net::HTTP::Get.new(path, @headers) 
            http = Net::HTTP.new(turi.host, turi.port) 
            req.basic_auth(user, pass) if user and pass
            if turi.scheme == "https" then
              http.use_ssl = true
              http.use_ssl = true
              http.verify_mode = OpenSSL::SSL::VERIFY_NONE
            end
            res = http.request(req)
            puts "DEBUG: fetched #{path}" if @debug
          end
        rescue Timeout::Error
          if rrtry < rtry then
            rrtry += 1
            puts "\nVERBOSE: request for \"#{path}\" timed out for #{rrtry} times - retrying..." if @verbose
            retry
          else
            puts "\nWARNING: request for \"#{path}\" timed out for #{rtry} times!" if !@quiet
            threads -= 1
            next
          end
        rescue =>e
          if rrtry < rtry then
            rrtry += 1
            puts "\nVERBOSE: request for \"#{path}\" produced \"#{e}\" for #{rrtry} times - retrying..." if @verbose
            retry
          else
            puts "\nWARNING: request for \"#{path}\" produced \"#{e}\" for #{rtry} times!" if !@quiet
          end
        rescue StandardError => msg
          puts "ERROR: #{msg}" if !@quiet
          Pidify.stop
          exit 0
        end
        puts "DEBUG: res.code = #{res.code}" if @debug
        puts "DEBUG: res.body = #{res.body}" if @debug
        # checksum stuff
        begin
          md5sum = Digest::MD5.hexdigest(res.body.to_s)
          puts "DEBUG: md5sum = #{md5sum}" if @debug
        rescue
          puts "WARNING: an error occoured while generating the md5sum of path = #{path}!" if !@quiet
        end
        m.synchronize do
          if save then
            # inserting data (csum, path, return-code) into the db
            @db.execute( "INSERT INTO tbl_results VALUES(NULL, (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1), \"#{md5sum}\", \"#{path}\", \"#{res.code}\")" )
          else
            md5sums.push(md5sum)
          end
        end
        if save then
          puts "DEBUG: executed SQL query: INSERT INTO tbl_results VALUES(NULL, (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1), \"#{md5sum}\", \"#{path}\", \"#{res.code}\")" if @debug
        end
        m.synchronize do
          print "." if !@quiet
          STDOUT.flush if !@quiet
          threads -= 1
        end
      end
    else
      sleep 0.1
      redo
    end
  end

  ts.each do |th| th.join end

  puts "" if save or @verbose

  dbclose(@db)

  return md5sums if !save

end # fetch()

# this func finally performs the checks
def check(scan_name, product, pversion, idrun, csums)
  
  matches = Hash.new()
  rcmatches = Hash.new()
  csumstr = ""
  ignorecnt = 0
  truecnt = 0
  retcodes = Array.new()

  if !idrun then
    @db = dbopen(SDB)
    csums = @db.execute( "SELECT csum, retcode FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1)" )
    puts "DEBUG: executed SQL query: SELECT csum FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1)" if @debug

    dbclose(@db)
  end

  csums.each_index do |x|
    retcodes.push(csums[x][1])
    if !idrun then
      csumstr = "#{csumstr}#{csums[x][0]}\",\""
    else
      csumstr = "#{csumstr}#{csums[x]}\",\""
    end
  end

  @db = dbopen(FDB)
  versions = @db.execute( "SELECT versionstring FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring LIKE \"#{pversion}\"" )

  puts "Checking gathered/stored checksums (##{csums.length}) against the selected product (#{product}) versions (##{versions.length}) checksums:" if !@quiet and idrun == false
  puts "DEBUG: executed SQL query: SELECT versionstring FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring LIKE \"#{pversion}\"" if @debug

  versions.each do |ver|
    m = @db.get_first_value( "SELECT count(path) FROM tbl_fprint WHERE product_id = (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\") AND csum IN (\"#{csumstr}\")" )
    puts "DEBUG: executed SQL query: SELECT count(path) FROM tbl_fprint WHERE product_id IN (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\") AND csum IN (\"#{csumstr}\")" if @debug
    actual_product = @db.get_first_value( "SELECT name FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\" LIMIT 1" )
    puts "DEBUG: executed SQL query: SELECT name FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\" LIMIT 1" if @debug
    c = @db.get_first_value( "SELECT count(path) FROM tbl_fprint WHERE product_id = (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\")" )
    puts "DEBUG: executed SQL query: SELECT count(path) FROM tbl_fprint WHERE product_id IN (SELECT DISTINCT id FROM tbl_product WHERE name LIKE \"#{product}\" AND versionstring = \"#{ver}\")" if @debug
    if !idrun then
      p = m.to_f / (c.to_f / 100.00)
      matches["#{actual_product}-#{ver}"] = [m.to_i, c.to_i, p.to_f]
    else
      p = m.to_f / (@idcount / 100.00)
      matches["#{actual_product}-#{ver}"] = [m.to_i, @idcount, p.to_f]
    end
    print "." if !@quiet
    STDOUT.flush if !@quiet
  end

  dbclose(@db)

  if !idrun then
    # doing some retcode stat calculation if verbose is enabled
    if @verbose then
      retcodes.sort.uniq.each do |code|
        tcnt = 0
        retcodes.each do |tcode|
          if tcode == code then
            tcnt += 1
          end
        end
        rcmatches["#{code}"] = tcnt
      end
    end
    puts ""

    return [matches, rcmatches]
  else
    return matches
  end

end # check()

# the main() function
def main()

  # if the arguments were omitted there is no need to go any further
  if ARGV.length == 0 then
    puts "What should I do? (try --help)"
    Pidify.stop
    exit 0
  end

  # check if our DBs are existant
  if !File.exist?(FDB) then
    puts "ERROR: The FingerPrint Database File (#{FDB}) can not be found!"
    Pidify.stop
    exit 0
  end

  if !File.exist?(SDB) then
    puts "ERROR: The Scan Database File (#{SDB}) can not be found!"
    Pidify.stop
    exit 0
  end

  # defining the valid options
  opts = GetoptLong.new(
    [ '--product', '-p', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--pversion', '-v', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--dump-products', '-P', GetoptLong::OPTIONAL_ARGUMENT ],
    [ '--store', '-s', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--fetch', '-f', GetoptLong::NO_ARGUMENT ],
    [ '--list', '-l', GetoptLong::OPTIONAL_ARGUMENT ],
    [ '--dry', '-d', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--threads', '-t', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--proxy', GetoptLong::OPTIONAL_ARGUMENT ],
    [ '--user-agent', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--outlines', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--timeout', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--retries', GetoptLong::REQUIRED_ARGUMENT ],
    [ '--any', GetoptLong::NO_ARGUMENT ],
    [ '--low-mem', GetoptLong::NO_ARGUMENT ],
    [ '--verbose', GetoptLong::NO_ARGUMENT ],
    [ '--debug', GetoptLong::NO_ARGUMENT ],
    [ '--quiet', GetoptLong::NO_ARGUMENT ],
    [ '--dbinfo', GetoptLong::NO_ARGUMENT ],
    [ '--version', GetoptLong::NO_ARGUMENT ],
    [ '--help', '-h', GetoptLong::NO_ARGUMENT ]
  )

  # well, thats because most users are lazy when it comes to
  # the correct order of the command opts ;)
  opts.ordering = GetoptLong::PERMUTE

  # vars that help to handle the arguments
  product = nil
  pversion = nil
  dproducts = nil
  store = nil
  fetcho = false
  list = nil
  dry = nil
  threads = 8
  proxy = nil
  pproxy = nil
  uagent = nil
  lines = 10
  tout = 10
  rtry = 3
  any = false
  # @verbose = false # already defined global
  # @debug = false # already defined global
  # @quiet = false # already defined global
  uri = nil
  scan_name = nil
  sinfo = "not used, yet."

  # opt processing
  begin
    opts.each do |opt, arg|
      case opt
        when '--product'
          product = arg
        when '--pversion'
          pversion = arg
        when '--dump-products'
          if arg == '' then dproducts = '%' else dproducts = arg end
          dump(dproducts) # exit 0
        when '--store'
          store = arg
        when '--fetch'
          fetcho = true
        when '--list'
          if arg == '' then list = '%' else list = arg end
          liststore(list) # exit 0
        when '--dry'
          dry = arg
        when '--threads'
          threads = arg.to_i
        when '--proxy'
          if arg == "ENV" then proxy = ENV['http_proxy'] else proxy = arg end
        when '--user-agent'
          uagent = arg
        when '--outlines'
          lines = arg
        when '--timeout'
          tout = arg.to_i
        when '--retries'
          rtry = arg.to_i
        when '--any'
          any = true
        when '--low-mem'
          @lowmem = true
        when '--verbose'
          @verbose = true
        when '--debug'
          @debug = true
        when '--quiet'
          @quiet = true
        when '--dbinfo'
          dbinfo() # exit 0
        when '--version'
          version() # exit 0
        when '--help'
          usage() # exit 0
      end
    end
  rescue # we do not care whats wrong with the opts - just yell! ;) (getoptlong should handle this)
    puts ""
    usage()
  end

  if threads < 1 || threads > 256 then
    puts "ERROR: the thread count should be greater than 1 and not higher than 256!"
    Pidify.stop
    exit 0
  end

  if tout < 1 || tout > 300 then
    puts "ERROR: the timeout should be greater than 0 and not higher than 300!"
    Pidify.stop
    exit 0
  end

  if rtry < 0 || rtry > 256 then
    puts "ERROR: the retry count should not be lower than 0 and not higher than 256!"
    Pidify.stop
    exit 0
  end

  if store then
    scan_name = "#{store}_#{@scanid}#{@tstamp}"
  else
    scan_name = "#{@scanid}#{@tstamp}"
  end

  if uagent then
    puts "VERBOSE: replacing default User-Agent with \"#{uagent}\" ..." if @verbose
    @headers['User-Agent'] = uagent
  end

  # ok, lets continue with the program flow...
  # check if its a dry or live run - otherwise there is nothing left to do
  # at this point of execution!
  if (ARGV.length == 1) then # is there an uri in one of our opts?
    given_url = ARGV[0]
    begin
      uri = URI.parse(given_url)
    rescue
      puts "ERROR: uri parsing failed!"
      Pidify.stop
      exit 0
    end
    scan_name = "#{scan_name}_#{uri.scheme}#{uri.host}#{uri.path}"
    @cancel_info[0] = scan_name
    @cancel_info[1] = nil # its not a dry run
    # TODO: the following proxy stuff is not used yet
    if proxy then
      begin
        pproxy = URI.parse(proxy)
      rescue
        puts "ERROR: proxy parsing failed!"
        Pidify.stop
        exit 0
      end
      if pproxy.scheme !~ /^(http|https)$/ then
        puts "ERROR: unknown proxy protocol \"#{pproxy.scheme}\"!"
        Pidify.stop
        exit 0
      end
    end
    if uri.scheme =~ /^(http|https)$/ then
      # if the low-mem option is not enabled we load the whole fprint db to the ram
      if @lowmem == false
        @memdb = loadb(dbopen(FDB))
      end
      if product == nil and any == true then
        product = '%'
      elsif product == nil and any == false and pversion == nil then
        product = identify_product(given_url, pproxy, threads, tout, rtry, save = false)
      end
      pversion = '%' if pversion == nil
      puts "DEBUG: calling tofetch(\"#{product}\", \"#{pversion}\")" if @debug
      paths = tofetch(product, pversion)
    else
      puts "ERROR: unknown protocol \"#{uri.scheme}\"!"
      Pidify.stop
      exit 0
    end
    # adding a uniq scan entry to the database
    @db = dbopen(SDB)
    @db.execute( "INSERT INTO tbl_store VALUES(NULL, \"#{scan_name}\", \"#{@tstamp}\", \"#{sinfo}\")" )
    puts "DEBUG: executed SQL query: INSERT INTO tbl_store VALUES(NULL, \"#{scan_name}\", \"#{@tstamp}\", \"#{sinfo}\")" if @debug
    dbclose(@db)
    puts "DEBUG: calling fetch(\"#{paths}\", \"#{given_url}\", \"#{pproxy}\", \"#{threads}\", \"#{tout}\", \"#{rtry}\", \"#{scan_name}\", \"false\")" if @debug
    fetch(paths, given_url, pproxy, threads, tout, rtry, scan_name, save = true)
    if !fetcho then
      puts "DEBUG: calling check(\"#{scan_name}\", \"#{product}\", \"#{pversion}\")" if @debug
      genoutput(check(scan_name, product, pversion, idrun = false, nil), lines)
    else
      puts "Fetching done - terminating." if !@quiet
    end
  elsif (dry != nil)
    product = '%' if product == nil
    pversion = '%' if pversion == nil
    genoutput(check(dry, product, pversion, idrun = false, nil), lines)
  else
    puts "ERROR: if you don't specify an URI then you should use -d/--dry!"
    puts "ERROR: otherwise there is nothing I can do for you!"
    Pidify.stop
    exit 0
  end

  # if the job is done and the user selected to store this run
  # we will leave it in the db. otherwise it will be deleted.
  if !store and !dry then
    puts "VERBOSE: deleting the temporary database entries for scan \"#{scan_name}\" ..." if @verbose
    @db = dbopen(SDB)
    @db.execute( "DELETE FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1)" )
    puts "DEBUG: executed SQL query: DELETE FROM tbl_results WHERE store_id = (SELECT id FROM tbl_store WHERE name = \"#{scan_name}\" LIMIT 1)" if @debug
    @db.execute( "DELETE FROM tbl_store WHERE name = \"#{scan_name}\"")
    puts "DEBUG: executed SQL query: DELETE FROM tbl_store WHERE name = \"#{scan_name}\"" if @debug
    dbclose(@db)
  elsif store and !dry
    puts "The scan got stored to the database with the name \"#{scan_name}\"." if !@quiet
  end

end # main()

# lets start by executing the main function ;)
main()

Pidify.stop

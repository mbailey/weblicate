require 'fileutils'
require 'json'
require 'uri'
require 'net/http'

# put file bundle into a dir
# append our own hostname onto it

class Har

  attr_accessor :dest_domain, :name

  def initialize(harfile, options={})
    @dest_domain = options[:dest_domain] || 'localhost'
    
    if File.exists? harfile
      contents = File.read(harfile)
    else
      contents = harfile
    end
    @name = File.basename(harfile, '.har')
    @har = JSON.parse(contents)
  end

  def hosts
    @har['log']['entries'].collect{ |e| 
      e['request']['headers'].select{|h| 
        h['name'] == 'Host'
      }.first['value'] 
    }.uniq.sort
  end

  def entries
    @har['log']['entries']
  end

  def files
    @har['log']['entries'].collect{|e| e['request']['url']}
  end

  def get_files
    # files.each {|file| get_file(file)}
    entries.each do |entry|
      if entry['response']['content']['text']
        contents = entry['response']['content']['text']
      else
        contents = `curl -s '#{entry['request']['url']}'`
      end 
      hosts.each { |host| contents.gsub! host, host+'.'+@dest_domain }
      save_file entry['request']['url'], contents 
    end
  end

  def save_file(url, contents)
    uri = URI.parse(url)
    dest = File.join("#{@name}-files", uri.host+'.'+@dest_domain, uri.path) 
    dest << 'index.html' if dest[-1,1] == '/'
    begin
      FileUtils.mkdir_p File.dirname dest
    rescue
      puts "Error! Could not create #{File.dirname dest}"
    end
    File.open(dest, "w") { |file| file.write contents }
  rescue
    puts "Failed to parse url (#{url})"
  end

  def vhosts
    hosts.collect do |host|
<<-EOF
<VirtualHost *:80>
  ServerName #{host}.#{@dest_domain}
  DocumentRoot /var/www/weblicate/#{@name}-files/#{host}.#{@dest_domain}
  <Directory /var/www/weblicate/#{@name}-files/#{host}.#{@dest_domain}>
    Order allow,deny
    Allow from all
  </Directory>
</VirtualHost>
EOF
    end
  end

  def hosts_file
    hosts.collect do |host|
      "127.0.0.1 #{host}.#{@dest_domain}\n"
    end
  end

  def dns
    hosts.collect do |host|
      zone = @dest_domain.sub /^.*?\./, ''
      name = host + '.' + @dest_domain.sub('.'+zone, '')
      "slicehost-dns add_cname #{zone} #{name} #{@dest_domain}.\n"
    end
  end

end

include pget
include unzip

# == Class: webapplications::install
#
# Installs CIC Web applications and configures them.
# CIC Web Applications Zip files (i.e. CIC_Web_Applications_2015_R3.iso) should be in a shared folder
# linked to C:\daas-cache
#
# === Parameters
#
# [ensure]
#   installed. No other values are currently supported.
#
#
# === Examples
#
#  class {'cicwebapplications=::install':
#   ensure => installed,
#  }
#
# === Authors
#
# Pierrick Lozach <pierrick.lozach@inin.com>
#
# === Copyright
#
# Copyright 2015, Interactive Intelligence Inc.
#

class webapplications::install (
  $ensure = installed,
)
{
  $daascache                        = 'C:/daas-cache/'
  $webapplicationszip               = "CIC_Web_Applications_${::cic_installed_major_version}_R${::cic_installed_release}.zip"

  if ($::operatingsystem != 'Windows')
  {
    err('This module works on Windows only!')
    fail('Unsupported OS')
  }

  $cache_dir = hiera('core::cache_dir', 'c:/users/vagrant/appdata/local/temp') # If I use c:/windows/temp then a circular dependency occurs when used with SQL
  if (!defined(File[$cache_dir]))
  {
    file {$cache_dir:
      ensure   => directory,
      provider => windows,
    }
  }

  case $ensure
  {
    installed:
    {
      ##################################
      # APPLICATION REQUEST ROUTING V3 #
      ##################################

      # Download Microsoft Application Request Routing Version 3 for IIS
      exec {'Download Microsoft Application Request Routing V3':
        command  => "\$wc = New-Object System.Net.WebClient;\$wc.DownloadFile('http://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi','${cache_dir}/requestRouter_amd64.msi')",
        path     => $::path,
        cwd      => $::system32,
        timeout  => 900,
        provider => powershell,
      }

      # Install the Microsoft Application Request Routing Version 3 for IIS
      package {'Microsoft Application Request Routing V3':
        ensure          => installed,
        source          => "${cache_dir}/requestRouter_amd64.msi",
        install_options => [
          '/l*v',
          'c:\\windows\\logs\\requestRouter_amd64.log',
        ],
        provider        => 'windows',
        require         => Exec['Download Microsoft Application Request Routing V3'],
      }

      # Enable proxy settings
      exec {'Enable proxy settings':
        command  => 'Set-WebConfigurationProperty -pspath \'IIS:\' -filter "system.webServer/proxy" -name "enabled" -value "True"',
        provider => powershell,
        require  => Package['Microsoft Application Request Routing V3'],
      }

      #TODO Verify that the Preserve client IP in the following header text field contains “X-Forwarded-For”
      # Verify that the Include TCP port from client IP checkbox is checked

      ######################
      # URL REWRITE MODULE #
      ######################

      # Download URL Rewrite module
      exec {'Download URL Rewrite module':
        command  => "\$wc = New-Object System.Net.WebClient;\$wc.DownloadFile('http://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi','${cache_dir}/rewrite_amd64.msi')",
        path     => $::path,
        cwd      => $::system32,
        timeout  => 900,
        provider => powershell,
      }

      # Install URL Rewrite module
      package {'Install URL Rewrite module':
        ensure          => installed,
        source          => "${cache_dir}/rewrite_amd64.msi",
        install_options => [
          '/l*v',
          'c:\\windows\\logs\\rewrite_amd64.log',
        ],
        provider        => 'windows',
        require         => Exec['Download URL Rewrite module'],
      }

      ###################
      # CREATE WEB SITE #
      ###################

      # Create folder in wwwroot
      file { 'C:/inetpub/wwwroot/ININApps':
        ensure => directory,
      }

      # Unzip web applications zip file
      unzip {'Unzip Web Applications':
        name        => "${daascache}${webapplicationszip}",
        destination => "${cache_dir}/ININApps",
        creates     => "${cache_dir}/ININApps/install.txt",
        require     => File['C:/inetpub/wwwroot/ININApps'],
      }

      # Copy the web_files folder to inetpub\wwwroot\ININApps
      exec {'Copy web_files':
        command  => "Copy-Item ${cache_dir}\\ININApps\\web_files\\* C:\\inetpub\\wwwroot\\ININApps\\ -Recurse -Force",
        provider => powershell,
        require  => [
          Unzip['Unzip Web Applications'],
          File['C:/inetpub/wwwroot/ININApps'],
        ],
      }

      # Create App Pool
      exec {'Add ININApps App Pool':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd add apppool /name:ININApps /managedRuntimeVersion:\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list apppool | findstr /l ININApps\"",
      }

      # Create virtual directory
      exec {'Add ININApps Virtual Directory':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd add vdir /app.name:\"Default Web Site/\" /path:/ININApps /physicalPath:C:\\inetpub\\wwwroot\\ININApps\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list vdir | findstr /l ININApps\"",
        require => [
          Exec['Copy web_files'],
          Exec['Add ININApps App Pool'],
        ],
      }

      ################
      # IIS SETTINGS #
      ################

      # Enable static content compression
      exec {'Enable static content compression':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:urlCompression /doStaticCompression:True\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config /section:urlCompression | findstr /l urlCompression doStaticCompression | findstr /l true\"",
      }

      # Update the maximum URL size in Request Filtering
      exec {'Set Max URL Size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxurl:8192\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config /section:requestfiltering | findstr /l \"requestLimits maxUrl\" | findstr 8192\"",
      }

      # Update the maximum query string size in Request Filtering
      exec{'Set Max Query String Size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxquerystring:8192\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config /section:requestfiltering | findstr /l \"requestLimits maxquerystring\" | findstr 8192\"",
      }

      ##############
      # WEB.CONFIG #
      ##############

      file {'C:/inetpub/wwwroot/ININApps/web.config':
        ensure  => present,
        content => template('webapplications/web.config.erb'),
        require => Exec['Add ININApps Virtual Directory'],
      }

      ##################
      # CACHE SETTINGS #
      ##################

      # Set frequentHitThreshold to 1
      /*
      exec {'Set frequentHitThreshold to 1':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/serverRuntime\' -name \'frequentHitThreshold\' -value \'1\'',
        provider => powershell,
      }

      # Set frequentHitTimePeriod to 00:10:00
      exec {'Set frequentHitTimePeriod to 00:10:00':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/serverRuntime\' -name \'frequentHitTimePeriod\' -value \'00:10:00\'',
        provider => powershell,
      }
      */

      # /client/lib content should expire after 365 days
      exec{'Set static content caching - client-lib':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config \"Default Web Site/ININApps/client/lib\" /section:staticContent /clientCache.cacheControlMode:UseMaxAge /clientCache.cacheControlMaxAge:365.00:00:00\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config \"Default Web Site/ININApps/client/lib\" /section:staticContent | findstr /l \"clientCache.cacheControlMode\" | findstr 365\"",
        require => Exec['Add ININApps Virtual Directory'],
      }

      # ONLY AVAILABLE IN 2016R1
      # /client/addins content should expire immediately
      /*
      exec{'Set static content caching - client-addins':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config \"Default Web Site/ININApps/client/addins\" /section:staticContent /clientCache.cacheControlMode:NoControl\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config \"Default Web Site/ININApps/client/addins\" /section:staticContent | findstr /l \"cacheControlMode\" | findstr /l NoControl\"",
        require => Exec['Add ININApps Virtual Directory'],
      }
      */

      # ONLY AVAILABLE IN 2016R1
      # /client/config content should expire immediately
      /*
      exec{'Set static content caching - client-config':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config \"Default Web Site/ININApps/client/config\" /section:staticContent /clientCache.cacheControlMode:NoControl\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config \"Default Web Site/ININApps/client/config\" /section:staticContent | findstr /l \"cacheControlMode\" | findstr /l NoControl\"",
        require => Exec['Add ININApps Virtual Directory'],
      }
      */

      # /client/index.html content should expire after 15 minutes
      exec{'Set static content caching - index.html':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config \"Default Web Site/ININApps/client/index.html\" /section:staticContent /clientCache.cacheControlMode:UseMaxAge /clientCache.cacheControlMaxAge:0.00:15:00 /commitpath:\"Default Web Site/ININApps/client\"\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config \"Default Web Site/ININApps/client/index.html\" /section:staticContent | findstr /l \"clientCache.cacheControlMode\" | findstr 15\"",
        require => Exec['Add ININApps Virtual Directory'],
      }

      # /client/appSettings.json content should expire immediately
      exec{'Set static content caching - appSettings.json':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config \"Default Web Site/ININApps/client/appSettings.json\" /section:staticContent /clientCache.cacheControlMode:NoControl /commitpath:\"Default Web Site/ININApps/client\"\"",
        path    => $::path,
        cwd     => $::system32,
        unless  => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd list config \"Default Web Site/ININApps/client/appSettings.json\" /section:staticContent | findstr /l \"clientCache.cacheControlMode\" | findstr NoControl\"",
        require => Exec['Add ININApps Virtual Directory'],
      }

      # Reset IIS
      exec {'iisreset':
        path        => 'C:/Windows/System32',
        refreshonly => true,
        require     => [
          Exec['Set static content caching - client-lib'],
          #Exec['Set static content caching - client-addins'],
          #Exec['Set static content caching - client-config'],
          Exec['Set static content caching - index.html'],
          Exec['Set static content caching - appSettings.json'],
        ],
      }

      # Add shortcut to Interaction Connect on the desktop
      file {'C:/users/vagrant/desktop/Interaction Connect.url':
        ensure  => present,
        content => "[InternetShortcut]\nURL=http://${hostname}/client",
        require => Exec['iisreset'],
      }

    }
    default:
    {
      fail("Unsupported ensure \"${ensure}\"")
    }
  }
}

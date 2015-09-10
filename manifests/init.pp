include pget
include unzip

# == Class: cicwebapplications::install
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
#   ensure                  => installed,
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

class cicwebapplications::install (
  $ensure = installed,
)
{

  $daascache                        = 'C:/daas-cache/'
  $currentversion                   = '2015_R3'
  $latestpatch                      = 'Patch8'

  $webapplicationszip               = "CIC_Web_Applications_${currentversion}.zip"
  $webapplicationslatestpatchzip    = "CIC_Web_Applications_${currentversion}_${latestpatch}.zip"
  
  $server                           = $::hostname
  
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

      # Copy the web_files folder to inetpub\wwwroot
      exec {'Copy web_files':
        command  => 'Copy-Item C:\\Users\\vagrant\\AppData\\Local\\Temp\\ININApps\\web_files\\* C:\\inetpub\\wwwroot\\ININApps\\ -Recurse -Force',
        provider => powershell,
        require  => Unzip['Unzip Web Applications'],
      }

      # Remove Default Web Site
      iis_site {'Default Web Site':
        ensure => absent,
      }

      # Create application pool (disable .Net runtime)
      iis_apppool {'ININApps':
        ensure                => present,
        managedruntimeversion => '',
      }

      # Create a new site called ININApps
      iis_site {'ININApps':
        ensure   => present,
        bindings => ['http/*:80:'],
        require  => [
          Iis_Site['Default Web Site'],
          Iis_Apppool['ININApps'],
        ],
      }

      # Create virtual application
      iis_app {'ININApps/':
        ensure          => present,
        applicationpool => 'ININApps',
        require         => Iis_Site['ININApps'],
      }

      # Create virtual directory
      iis_vdir {'ININApps/':
        ensure       => present,
        iis_app      => 'ININApps/',
        physicalpath => 'C:\inetpub\wwwroot\ININApps',
        require      => Iis_App['ININApps/'],
      }

      ##################################
      # APPLICATION REQUEST ROUTING V3 #
      ##################################

      # Download Microsoft Application Request Routing Version 3 for IIS
      pget {'Download Microsoft Application Request Routing V3':
        source => 'http://download.microsoft.com/download/E/9/8/E9849D6A-020E-47E4-9FD0-A023E99B54EB/requestRouter_amd64.msi',
        target => $cache_dir,
      }

      # Install the Microsoft Application Request Routing Version 3 for IIS
      package {'Microsoft Application Request Routing V3':
        ensure          => installed,
        source          => "${cache_dir}/requestRouter_x64.msi",
        install_options => [
          '/l*v',
          'c:\\windows\\logs\\requestRouter_x64.log',
        ],
        provider        => 'windows',
        require         => Pget['Microsoft Application Request Routing V3'],
      }

      # Enable proxy settings
      exec {'Enable proxy settings':
        command  => 'Set-WebConfigurationProperty -pspath \'IIS:\' -filter "system.webServer/proxy" -name "enabled" -value "True"',
        provider => powershell,
        require  => Package['Microsoft Application Request Routing V3'],
      }

      #####################################
      # UPDATE REQUEST FILTERING SETTINGS #
      #####################################
      # TODO: Use Powershell to do this

      # Update the maximum URL size in Request Filtering
      exec{'set-max-url-size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxurl:8192\"",
        path    => $::path,
        cwd     => $::system32,
        require => Iis_Vdir['ININApps/'],
      }

      # Update the maximum query string size in Request Filtering
      exec{'set-max-query-string-size':
        command => "cmd.exe /c \"%windir%\\system32\\inetsrv\\appcmd set config /section:requestfiltering /requestlimits.maxquerystring:8192\"",
        path    => $::path,
        cwd     => $::system32,
        require => Iis_Vdir['ININApps/'],
      }
      
      ######################
      # URL REWRITE MODULE #
      ######################

      # Download URL Rewrite module
      pget {'Download URL Rewrite module':
        source => 'http://download.microsoft.com/download/C/9/E/C9E8180D-4E51-40A6-A9BF-776990D8BCA9/rewrite_amd64.msi',
        target => $cache_dir,
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
        require         => Pget['Download URL Rewrite module'],
      }

      ##############
      # WEB.CONFIG #
      ##############

      # Add web.config file
      file {'web.config':
        ensure  => present,
        path    => 'C:/inetpub/wwwroot/ININApps',
        content => template('inin-webapplications/web.config.erb'),
        require => [
          Iis_Vdir['ININApps/'],
          Exec['Enable proxy settings'],
          Package['Install URL Rewrite module'],
        ],
      }

      # Add site server variables
      file_line {'ININApps Server Variables':
        ensure  => present,
        path    => 'C:/Windows/System32/inetsrv/config/applicationHost.config',
        line    => " \
          <location path=\"ININApps\"> \
            <system.webServer> \
              <rewrite> \
                <allowedServerVariables> \
                  <add name=\"WEB_APP\" /> \
                  <add name=\"ICWS_HOST\" /> \
                  <add name=\"HTTP_ININ-ICWS-Original-URL\" /> \
                </allowedServerVariables> \
              </rewrite> \
            </system.webServer> \
          </location>",
        after   => '</system.webServer>',
        require => File['web.config'],
      }

      exec {'iisreset':
        path        => 'C:/Windows/System32',
        refreshonly => true,
        require     => File_Line['ININApps Server Variables'],
      }

    }
    default:
    {
      fail("Unsupported ensure \"${ensure}\"")
    }
  }
}
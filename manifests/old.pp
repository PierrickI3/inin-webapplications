/*
      ####################
      # SERVER VARIABLES #
      ####################

      # Add WEB_APP allowed server variable
      exec{'Add WEB_APP allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'WEB_APP\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="WEB_APP"]\' | Select name | Select-String WEB_APP) { Exit 1 }',
      }

      # Add ICWS_HOST allowed server variable
      exec{'Add ICWS_HOST allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'ICWS_HOST\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="ICWS_HOST"]\' | Select name | Select-String ICWS_HOST) { Exit 1 }',
      }

      # Add HTTP_ININ-ICWS-Original-URL allowed server variable
      exec{'Add HTTP_ININ-ICWS-Original-URL allowed server variables':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/allowedServerVariables" -name "." -value @{name=\'HTTP_ININ-ICWS-Original-URL\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/allowedServerVariables[@name="HTTP_ININ-ICWS-Original-URL"]\' | Select name | Select-String HTTP_ININ-ICWS-Original-URL) { Exit 1 }',
      }

      ###############
      # REWRITE MAP #
      ###############

      # Add MapScheme rewrite map
      exec {'Add MapScheme rewrite map':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/rewriteMaps" -name "." -value @{name=\'MapScheme\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfiguration -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' | Select name | Select-String MapScheme) { Exit 1 }',
        require  => [
          Exec['Add WEB_APP allowed server variables'],
          Exec['Add ICWS_HOST allowed server variables'],
          Exec['Add HTTP_ININ-ICWS-Original-URL allowed server variables'],
        ],
      }

      # Add https map entry
      exec {'Add https map entry':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\'  -filter "system.webServer/rewrite/rewriteMaps/rewriteMap[@name=\'MapScheme\']" -name "." -value @{key=\'on\';value=\'https\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' -name Collection  | Select-Object value | Select-String -pattern "https\b") { Exit 1 }',
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Add http map entry
      exec {'Add http map entry':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\'  -filter "system.webServer/rewrite/rewriteMaps/rewriteMap[@name=\'MapScheme\']" -name "." -value @{key=\'off\';value=\'http\'}',
        provider => powershell,
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/rewriteMaps/rewriteMap[@name="MapScheme"]\' -name Collection  | Select-Object value | Select-String -pattern "http\b") { Exit 1 }',
        require  => Exec['Add MapScheme rewrite map'],
      }

      ########################
      # INBOUND REWRITE RULE #
      ########################

      # Add inbound rule
      exec {'Add inbound rule':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/globalRules" -name "." -value @{name=\'inin-api-rewrite\';patternSyntax=\'Regular Expressions\';stopProcessing=\'True\'}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/globalRules/rule[@name=\'inin-api-rewrite\']" -Name "." | Select-Object name | Select-String inin-api-rewrite) { Exit 1 }',
        provider => powershell,
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Set inbound rule type to Rewrite
      exec {'Set inbound rule type':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/action\' -name \'type\' -value \'Rewrite\'',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Set inbound rule regex pattern
      exec {'Set inbound rule regex pattern':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/match\' -name \'url\' -value \'(?:^(.*/)api|^api)/([^/]+)(/.*)\'',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Set inbound rule URL
      exec {'Set inbound rule URL':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/action\' -name \'url\' -value \'https://{ICWS_HOST}:8018{R:3}\'',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/globalRules/rule[@name=\'inin-api-rewrite\']/action" -Name "url" | Select-String "https://{ICWS_HOST}:8018{R:3}") { Exit 1 }',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Set inbound rule ignore case
      exec {'Set inbound rule ignore case':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/match\' -name \'ignoreCase\' -value \'True\'',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Add WEB_APP inbound rule server variable
      exec {'Add WEB_APP inbound rule server variable':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -name "." -value @{name="WEB_APP";value="{R:1}"}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -Name "Collection" | Select-Object name | Select-String -Pattern "WEB_APP\b") { Exit 1 }',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Add ICWS_HOST inbound rule server variable
      exec {'Add ICWS_HOST inbound rule server variable':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -name "." -value @{name="ICWS_HOST";value="{R:2}"}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -Name "Collection" | Select-Object name | Select-String -Pattern "ICWS_HOST\b") { Exit 1 }',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Add HTTP_ININ-ICWS-Original-URL inbound rule server variable
      exec {'Add HTTP_ININ-ICWS-Original-URL inbound rule server variable':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -name "." -value @{name="HTTP_ININ-ICWS-Original-URL";value="{MapScheme:{HTTPS}}://{HTTP_HOST}{UNENCODED_URL}";replace="False"}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/serverVariables\' -Name "Collection" | Select-Object name | Select-String -Pattern "HTTP_ININ-ICWS-Original-URL\b") { Exit 1 }',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Set inbound rule append query string
      exec {'Set inbound rule append query string':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/globalRules/rule[@name="inin-api-rewrite"]/action\' -name \'appendQueryString\' -value \'True\'',
        provider => powershell,
        require  => Exec['Add inbound rule'],
      }

      # Set inbound rule log rewritten url (?? Can't find entry in Windows 2012R2)

      ###############################
      # FIRST OUTBOUND REWRITE RULE #
      ###############################
      
      # Add outbound rule #1
      exec {'Add outbound rule #1':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/outboundRules" -name "." -value @{name=\'inin-cookie-paths\';type=\'Server Variable\';stopProcessing=\'False\'}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/outboundRules/rule[@name=\'inin-cookie-paths\']" -Name "." | Select-Object name | Select-String inin-cookie-paths) { Exit 1 }',
        provider => powershell,
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Set outbound rule #1 server variable name
      exec {'Set outbound rule #1 server variable name':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-cookie-paths"]/match\' -name \'serverVariable\' -value \'RESPONSE_Set_Cookie\'',
        provider => powershell,
        require  => Exec['Add outbound rule #1'],
      }

      # Set outbound rule #1 server variable value
      exec {'Set outbound rule #1 server variable value':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-cookie-paths"]/match\' -name \'pattern\' -value \'(.*)Path=(/icws.*)\'',
        provider => powershell,
        require  => [
          Exec['Add outbound rule #1'],
          Exec['Set outbound rule #1 server variable name'],
        ],
      }

      # Set outbound rule #1 ignore case
      exec {'Set outbound rule #1 ignore case':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-cookie-paths"]/match\' -name \'ignoreCase\' -value \'True\'',
        provider => powershell,
        require  => Exec['Add outbound rule #1'],
      }

      # Set outbound rule #1 action type
      exec {'Set outbound rule #1 action type':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-cookie-paths"]/action\' -name \'type\' -value \'Rewrite\'',
        provider => powershell,
        require  => Exec['Add outbound rule #1'],
      }

      # Set outbound rule #1 action value
      exec {'Set outbound rule #1 action value':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-cookie-paths"]/action\' -name \'value\' -value \'{R:1}Path=/{WEB_APP}api/{ICWS_HOST}{R:2}\'',
        provider => powershell,
        require  => Exec['Add outbound rule #1'],
      }

      ################################
      # SECOND OUTBOUND REWRITE RULE #
      ################################
      
      # Add outbound rule #2
      exec {'Add outbound rule #2':
        command  => 'Add-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/outboundRules" -name "." -value @{name=\'inin-location-paths\';type=\'Server Variable\';stopProcessing=\'False\'}',
        onlyif   => 'if (Get-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter "system.webServer/rewrite/outboundRules/rule[@name=\'inin-location-paths\']" -Name "." | Select-Object name | Select-String inin-location-paths) { Exit 1 }',
        provider => powershell,
        require  => Exec['Add MapScheme rewrite map'],
      }

      # Set outbound rule #2 server variable name
      exec {'Set outbound rule #2 server variable name':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-location-paths"]/match\' -name \'serverVariable\' -value \'RESPONSE_location\'',
        provider => powershell,
        require  => Exec['Add outbound rule #2'],
      }

      # Set outbound rule #2 server variable value
      exec {'Set outbound rule #2 server variable value':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-location-paths"]/match\' -name \'pattern\' -value \'^/icws/.*\'',
        provider => powershell,
        require  => [
          Exec['Add outbound rule #2'],
          Exec['Set outbound rule #2 server variable name'],
        ],
      }

      # Set outbound rule #2 ignore case
      exec {'Set outbound rule #2 ignore case':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-location-paths"]/match\' -name \'ignoreCase\' -value \'True\'',
        provider => powershell,
        require  => Exec['Add outbound rule #2'],
      }

      # Set outbound rule #2 action type
      exec {'Set outbound rule #2 action type':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-location-paths"]/action\' -name \'type\' -value \'Rewrite\'',
        provider => powershell,
        require  => Exec['Add outbound rule #2'],
      }

      # Set outbound rule #2 action type value
      exec {'Set outbound rule #2 action type value':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/rewrite/outboundRules/rule[@name="inin-location-paths"]/action\' -name \'value\' -value \'/{WEB_APP}api/{ICWS_HOST}{R:0}\'',
        provider => powershell,
        require  => Exec['Add outbound rule #2'],
      }

      ########################
      # PERFORMANCE SETTINGS #
      ########################

      # Set frequentHitThreshold to 1
      exec {'Set frequentHitThreshold to 1':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/serverRuntime\' -name \'frequentHitThreshold\' -value \'1\'',
        provider => powershell,
        require  => Iis_Vdir['ININApps/'],
      }

      # Set frequentHitTimePeriod to 00:10:00
      exec {'Set frequentHitTimePeriod to 00:10:00':
        command  => 'Set-WebConfigurationProperty -pspath \'MACHINE/WEBROOT/APPHOST\' -filter \'system.webServer/serverRuntime\' -name \'frequentHitTimePeriod\' -value \'00:10:00\'',
        provider => powershell,
        require  => Iis_Vdir['ININApps/'],
      }
*/
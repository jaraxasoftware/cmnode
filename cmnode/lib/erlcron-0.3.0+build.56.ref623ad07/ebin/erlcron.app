{application,erlcron,
             [{description,"Erlang Implementation of cron"},
              {vsn,"0.3.0+build.56.ref623ad07"},
              {modules,[ecrn_agent,ecrn_app,ecrn_control,ecrn_cron_sup,
                        ecrn_reg,ecrn_sup,ecrn_test,ecrn_util,erlcron]},
              {registered,[ecrn_agent]},
              {applications,[kernel,stdlib]},
              {mod,{ecrn_app,[]}}]}.

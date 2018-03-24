-module(cmsession_notify_effect).
-export([ effect_info/0,
          effect_apply/2
        ]).

effect_info() -> notify.
effect_apply(Data, #{ id := Id }) ->
    cmsession:tell(Id, Data).

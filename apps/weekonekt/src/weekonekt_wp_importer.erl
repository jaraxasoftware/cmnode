-module(weekonekt_wp_importer).
-export([import/1, handle/2]).

import(Data) ->
    Res = cmxml:parse(Data, fun weekonekt_wp_parser:event/3, #{ state => none,
                                                          callback => {?MODULE, handle},
                                                          stats => #{ images => 0,
                                                                      reviews => 0 }
                                                        }),
    
    case Res of 
        {ok, {ok, Stats}, _} -> {ok, Stats};
        Other -> Other
    end.

handle(#{ id := Id, 
         url := Url, 
         title := Title, 
         date := Date,
         type := "attachment" }, #{ images := Images }=Stats) ->
    
    BinId = cmkit:to_bin(Id),
    BinUrl = cmkit:to_bin(Url),
    PKey = {image, BinId},
    Item = #{ id => BinId,
              url => BinUrl,
              title => cmkit:uniconvert(Title),
              date => cmkit:to_millis(Date) },
    
    weekonekt:import_image(BinId, Url),
    cmdb:put_new(weekonekt, [{PKey, Item}]),
    Stats#{ images => Images + 1 };

handle(#{ title := "About me" }, Stats) -> Stats;
handle(#{ title := "Contact" }, Stats) -> Stats;


handle(#{ id := Id, 
              content := #{ options := Opts,
                            images := Images },
              geo := #{ lat := Lat, lon := Lon },
              title := Title, 
              date := Date,
              type := "page" }, #{ reviews := Reviews }=Stats) ->
        
    ImageIds = lists:map(fun cmkit:to_bin/1, Images),
    
    
    
    CoverImage = case ImageIds of 
                     [] -> none;
                     [First|_] -> First
                 end,

    BinId = cmkit:to_bin(Id),
    PKey = {review, BinId},
    Item = #{ id => BinId,
              title => cmkit:uniconvert(Title),
              lat => Lat,
              lon => Lon,
              date => cmkit:to_millis(Date),
              options => Opts,
              cover => CoverImage,
              images => lists:map(fun cmkit:to_bin/1, Images) },

    cmdb:put_new(weekonekt, [{PKey, Item}]),
    Stats#{ reviews => Reviews + 1 };
    
handle(#{ type := "nav_menu_item" }, Stats) -> Stats;
handle(#{ type := "feedback" }, Stats) -> Stats;


handle(Item, Stats) -> 
    cmkit:warning({weekonekt_wp_importer, ignore, Item}),
    Stats.



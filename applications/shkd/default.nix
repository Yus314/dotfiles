{
  services.skhd = {
    enable = true;
    skhdConfig = ''
                                                        # launch application 
                                    				#	alt - return : open -na "''${HOME}/Applications/Home Manager Apps/Alacritty.app"
            											alt - e : open -na "/Users/kakinumayuusuke/.nix-profile/bin/emacs"
                              							cmd + alt - s : yabai --load-sa
      			alt - e : emacs

                                                            # focus window
                                                            alt - h : yabai -m window --focus west
                                                            alt - j : yabai -m window --focus south
                                                            alt - k : yabai -m window --focus north
                                                            alt - l : yabai -m window --focus east
                                                            alt - p : yabai -m window --focus prev
                                                            alt - n : yabai -m window --focus next

                                                            # swap window
                                                            shift + alt - h : yabai -m window --swap west
                                                            shift + alt - j : yabai -m window --swap south
                                                            shift + alt - k : yabai -m window --swap north
                                                            shift + alt - l : yabai -m window --swap east

                                                            # move window
                                                            shift + cmd - h : yabai -m window --warp west
                                                            shift + cmd - j : yabai -m window --warp south
                                                            shift + cmd - k : yabai -m window --warp north
                                                            shift + cmd - l : yabai -m window --warp east

                                                      	  # close window
                                                      	  shift + cmd - q : yabai -m window --close

                                                			  # Create space on the active display
                                                			  alt - s : yabai -m space --create

                                                            # focus desktop
                                                            alt - 1 : yabai -m space --focus 1
                                                            alt - 2 : yabai -m space --focus 2
                                                            alt - 3 : yabai -m space --focus 3
                                                            alt - 4 : yabai -m space --focus 4
                                                            alt - 5 : yabai -m space --focus 5
                                                            alt - 6 : yabai -m space --focus 6
                                                            alt - 7 : yabai -m space --focus 7
                                                            alt - 8 : yabai -m space --focus 8
                                                            alt - 9 : yabai -m space --move prev
                                                            alt - 0 : yabai -m space --move next

                        									# Move spaces (require sa)
                  										  shift + alt - 1 : yabai -m window --space 1
                  										  shift + alt - 2 : yabai -m window --space 2
                  										  shift + alt - 3 : yabai -m window --space 3
                  										  shift + alt - 4 : yabai -m window --space 4
                  										  shift + alt - 5 : yabai -m window --space 5
                  										  shift + alt - 6 : yabai -m window --space 6
                  										  shift + alt - 7 : yabai -m window --space 7
                  										  shift + alt - 8 : yabai -m window --space 8
                  										  shift + alt - 9 : yabai -m window --space 9
                  										  shift + alt - 0 : yabai -m window --space 10

                                                            # resize
                                                            shift + alt - a : yabai -m window --resize right:-100:0 || yabai -m window --resize left:-100:0
                                                            shift + alt - s : yabai -m window --resize bottom:0:100 || yabai -m window --resize top:0:100
                                                            shift + alt - w : yabai -m window --resize bottom:0:-100 || yabai -m window --resize top:0:-100
                                                            shift + alt - d : yabai -m window --resize right:100:0 || yabai -m window --resize left:100:0
    '';
  };
}

{pkgs ,epkgs}:
let
sources = pkgs.callPackage ../../../_sources/generated.nix {inherit (pkgs) fetchFromGitHub;};
in
{
    gcal = epkgs.melpaBuild {
      pname = "gcal";
      version = "0.0.1";
      src = sources.gcal.src;
      ignoreCompilationError =false;
     };
        ol-emacs-slack = epkgs.melpaBuild {
      pname = "ol-emacs-slack";
      version = "0.0.1";
      src = sources.ol-emacs-slack.src;

      packageRequires = with epkgs; [
	dash
	s
	];
      ignoreCompilationError =false;
	 };
        org-modern-indent = epkgs.melpaBuild {
      pname = "org-modern-indent";
      version = "0.0.1";
      src = sources.org-modern-indent.src;
      ignoreCompilationError =false;
	 };
         org-roam-review= epkgs.melpaBuild {
      pname = "org-roam-review";
      version = "0.0.1";
      src = sources.org-roam-review.src;

      packageRequires = with epkgs; [
        dash
	org-drill
        org-roam
	ts
	ht
      ];
      files = ''("lisp/org-roam-review.el" "lisp/org-tags-filter.el" "lisp/plisty.el")'';    
      ignoreCompilationError =false;
	 };
        typst-preview = epkgs.melpaBuild {
      pname = "typst-preview";
      version = "0.0.1";
      src = sources.typst-preview.src;

      packageRequires = with epkgs; [
	websocket
      ];
      
      ignoreCompilationError =false;
      };
  }

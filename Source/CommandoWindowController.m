/*************************************************************************************************/
/* Copyright 2005 Shane D. Looker.                                                               */
/*                                                                                               */
/* This source code is being made available as free sample code as is. No warantee, express or   */
/* implied is made as to the quality or correctness of this code.                                */
/* This source code may be freely distributed as long as this copyright notice remains attached. */
/* Check http://www.MacCommando.com for updated source.                                          */
/*************************************************************************************************/
#import "CommandoWindowController.h"
#import <string>
#import <fstream>
#import	"CmdoControl.h"
#if	DO_PROFILE
#import "Profiler.h"
#endif


extern int	gArgc;
extern char **gArgv;
extern char** environ;

int	gMaxColumnWidth;			// Hack value so the controls should figure out their max width

NSMutableDictionary *gSubstitutionDictionary;
NSMutableDictionary	*gRadioDict;
NSMutableDictionary *gAllOptionControls;

void	signalCatcher(int signal);
int		gChildProcessID = -1;		// When we sub-task out, we set this to the pid of the child process for signal handling
NSTask	*gSubTask = nil;

@implementation CommandoWindowController


- (void) awakeFromNib
{
	BOOL	isOK;
	
	if ((gArgc < 2) || ([self findShell] == FALSE))	//	There is no command name given or no shell found
	{
		printf("Command usage:\ncmdo [toolName]\n... [toolName]\n", gArgv[1]);
		[self doCancel: self];
	}
	
	// If gArgv[1] starts with -psn, this was launched by double clicking. Show a dialog then exit
	if (strncmp(gArgv[1], "-psn", 4) == 0)		// They compared equal, bail out!
	{
		NSAlert	*deathAlert = [[NSAlert alloc] init];
		[deathAlert addButtonWithTitle: @"Quit"];
		[deathAlert setMessageText: @"Commando only runs from the command line."];
		[deathAlert setInformativeText: @"Double-clicking Commando only leads here. Don't do it again."];
		[deathAlert setAlertStyle: NSCriticalAlertStyle];
		[deathAlert runModal];
	
		[self doCancel: self];
	}

#if	DO_PROFILE
	OSErr	profErr =  ProfilerInit(collectDetailed, bestTimeBase, 200, 200);
#endif
	mStdinTypeTag	= kInputPopupTerminal;
	mStdoutTypeTag	= kOutputPopupTerminal;
	mStderrTypeTag	= kStderrPopupToOutput;


	// First remove all the tabs
	
	[myTabView removeTabViewItem: [myTabView tabViewItemAtIndex: 1]];
	[myTabView setDelegate: self];
	gMaxColumnWidth = (NSWidth([myTabView frame]) / 2) - 20;
	

	// Now create our global dictionaries
	gSubstitutionDictionary = [[NSMutableDictionary alloc] initWithCapacity: 40];
	gRadioDict = [[NSMutableDictionary alloc] initWithCapacity: 40];
	gAllOptionControls = [[NSMutableDictionary alloc] initWithCapacity: 40];
	
	// First we need to find and load the proper data file
	mToolParser	= [[ToolParser alloc] init];
	if (mToolParser == nil)	// Parser failed to load. Very bad
	{
		printf("Parser initialization failure. Very bad thing.");
		[self doCancel: self];
	}
	
	isOK = [mToolParser loadCommandDefinitionArgc: gArgc Argv: gArgv];
	if (isOK == FALSE)	// No data file to parse
	{
		printf("Unable to find commando data for %s\n", gArgv[1]);
		[self doCancel: self];
	}
	
	mPanelDictionary = [mToolParser panelDictionary];	// Build the list of tab panels

	[[self window] setTitle: [NSString stringWithCString: gArgv[1]]];

	// Only if I last this far do I want to force the interface to the front
	ProcessSerialNumber	psn;
	MacGetCurrentProcess(&psn);
	SetFrontProcess(&psn);

	[self buildInterfaceTabs];	// Throw the interface together
	[self displayCommandLine];	// Show the output command line

	NSString	*tempCreditLine = [mToolParser creditLine];
	if ((tempCreditLine == nil) || ([tempCreditLine length] == 0))
		[mCreditBox setHidden: TRUE];
	else
		[mCreditBox setTitleWithMnemonic: tempCreditLine ];
	
	// Now tell the notification center that we want to listen for changes in from the edit text boxes
	NSNotificationCenter	*theNC = [NSNotificationCenter defaultCenter];
	[theNC addObserver: self selector: @selector(textChangedNotificationHandler:) name:@"NSTextDidChangeNotification" object: nil];


	// Install a bunch of signal handlers so we can clean things up nicely.
	signal(SIGHUP, signalCatcher);
	signal(SIGINT, signalCatcher);
	signal(SIGKILL, signalCatcher);
	signal(SIGQUIT, signalCatcher);
	signal(SIGABRT, signalCatcher);
	signal(SIGTERM, signalCatcher);

#if	DO_PROFILE
	profErr = ProfilerDump("\pCommandoProfile.prof");
#endif
}


- (IBAction)doCancel:(id)sender
{
	[self returnTerminalToFront];
	[[NSApplication sharedApplication] terminate: self];
}


- (IBAction)doDisplay:(id)sender
{
	NSMutableString	*commandStr = [self buildExecutionString];

	[self returnTerminalToFront];
	printf("%s\n", [commandStr cString]);
	[self doCancel: sender];

	[[NSApplication sharedApplication] terminate: self];
}


- (IBAction)doExecute:(id)sender
{
	NSTask	*subTask;
//	NSString	*pathStr = @"/bin/tcsh";
	
	NSMutableString	*commandStr = [self buildExecutionString];
//	[argArray removeObjectAtIndex: 0];
	NSMutableArray	*argArray = [NSMutableArray arrayWithObject: commandStr];

	// IMPORTANT. All the sells need to have the first argument as -c to indicate that the next item is the 
	// command to be executed. The command lineis apssed as a single string in an array. (Making a total of
	// two arguments to the shell. i.e. tcsh -c "ls -al" )
	[argArray insertObject: [NSString stringWithString: @"-c"] atIndex:0];
	
	printf("%s\n", [commandStr cString]);	// Write the command back to stdout (i.e. Terminal)
	subTask = [NSTask launchedTaskWithLaunchPath:mShellPathStr arguments: argArray];
	gChildProcessID = [subTask processIdentifier];
	gSubTask = subTask;
	
	[self returnTerminalToFront];
	[subTask waitUntilExit];

	[self returnTerminalToFront];

	[[NSApplication sharedApplication] terminate: self];
}


- (void) returnTerminalToFront
{
	char		bigArray[1024];
	
	ProcessInfoRec	procInfo;
	procInfo.processName = nil;
	procInfo.processAppRef = nil;
	procInfo.processLocation = bigArray;
	procInfo.processInfoLength = sizeof(procInfo);
	
	ProcessSerialNumber	psn;
	MacGetCurrentProcess(&psn);
	GetProcessInformation(&psn, &procInfo);
	
	SetFrontProcess(&procInfo.processLauncher);	// Return to make the parent frontmost
}


/* buildInterfaceTabs
	This method is probably the most complicated in Commando. In this method I have to create an interface
	dynamically based on the parsed data file. I walk over the list of panels and create each one, then I
	populate the tab
*/
- (void) buildInterfaceTabs
{	
	int count = [mPanelDictionary count];
	int i; 
	NSString	*key;
	
	for (i = 0; i < count; i++)		// each of these is a separate tab
	{
		key = [mPanelDictionary keyAtIndex: i];
		
		NSMutableArray *tabControlList = [mPanelDictionary objectForKey: key];
		
		NSTabViewItem	*aTabView = [NSTabViewItem new];
		[aTabView setLabel: key];
		[myTabView insertTabViewItem: aTabView atIndex: i];
		
		NSRect	tabViewRect = [myTabView contentRect]; // bounds];

		AssociatedTable *myCmdoControls = [[AssociatedTable	alloc] init];
		NSMutableSet	*goodControls;
		[self fillControlTable: &myCmdoControls andUniqueSet: &goodControls fromTabControlList: tabControlList];

		// Now we have a list of all the controls associated with the CmndoControls and a unique list
		// of controls. This will prevent us from adding multiple copies of controls that are inside
		// and NSMatrix
		int max = [myCmdoControls count];
		NSView	*subView = [aTabView view];
		float	subViewBottom = 0;	// Use 0 because inside the subView it is 0, not origin NSMinY(tabViewRect);
		float	subViewTop = NSHeight(tabViewRect); // same reason as abomve NSMaxY(tabViewRect);
		float	lastControlBottom = subViewTop;
		float	currentLeftEdge = 20.0; // NSMinX(tabViewRect) + 20.0;

		for (int controlIndex = 0; controlIndex < max; controlIndex++)
		{
			float	fHeight;
			NSControl	*aControl = [myCmdoControls objectAtIndex: controlIndex];

			if ([goodControls containsObject: aControl])
			{
				[goodControls removeObject: aControl];	// Take it away before we process this index
														// in the AssociatedTable
				CmdoControl *cCon = [myCmdoControls keyAtIndex: controlIndex];
				NSView *tempView;
				if ([[cCon control] isKindOfClass: [NSMatrix class]])	// I want to box this up
				{
					NSBox *theBox = [[NSBox alloc] init];
					[theBox setBoxType: NSBoxSecondary];
				//	[theBox setBorderType: NSLineBorder];
					[theBox setTitlePosition: NSNoTitle];// ;
					[theBox setContentView: [cCon control]];
					[theBox sizeToFit];

					tempView = theBox;
					fHeight = NSHeight([theBox frame]);
				}
				else {
						tempView = [cCon control];		// Get the actual control from CmdoControl and get the 
						fHeight = [cCon height];		// height for the cmdo control object
				}
				
				[subView addSubview: tempView];
				
			//	[controlInfo replaceObjectAtIndex: 0 withObject: aControl];	// Save off the reference to the button
			//	float	fHeight = [cCon height]; // [aControl frame];
				
				// Now given the frame, I can compute where it should go based on the size
				// of the tab view and where the last control was.
				// int height = std::max((int) NSHeight(checkRect), 22);
				int height = (int) fHeight + 3.0; // I want 3 pixels between each control

				if ((lastControlBottom - height) < subViewBottom)	// Need to swtich columns and start at top again
				{
					lastControlBottom = subViewTop;
					currentLeftEdge += NSWidth(tabViewRect) / 2.0;	// This leaves us offset from the left edge
				}

				lastControlBottom -= height;
				[tempView setFrameOrigin: NSMakePoint(currentLeftEdge, lastControlBottom) ];
			}
		}
		
	}
	
	[myTabView selectFirstTabViewItem: self];
}


- (void) fillControlTable: (AssociatedTable**) theCmdoControls andUniqueSet: (NSMutableSet**) uniqueSet fromTabControlList: (NSMutableArray*) tabControlList
{
	int max = [tabControlList count];
	AssociatedTable *myCmdoControls = [[AssociatedTable	alloc] init];
	for (int controlIndex = 0; controlIndex < max; controlIndex++)	// Go make all the controls I need first.
	{																// This is important because radio controls get
																	// grouped as a single NSMatrix
		NSMutableArray *controlInfo = [tabControlList objectAtIndex: controlIndex];
		NSString *controlType = [controlInfo objectAtIndex: kCmdoControlType];
		CmdoControl *cCon = [CmdoControl initWithData: controlInfo forController: self];
		// [cCon control may return NSMatrix eventually, and I only want a singleton for those
		// I need an ordered list of controls to test against before I decide if I keep this CmdoControl
		// in the list
		if (cCon != nil)
			[myCmdoControls setObject: [cCon control] forKey: cCon ];
	}
	// Now I have an AssociatedTable for all the CmdoControls and controls, so I can make a set
	// based on the controls and use that to test for uniqueness in the tab. (Thus allowing only a
	// single instance for an NSMatrix
	NSMutableSet	*goodControls = [NSMutableSet setWithArray: [myCmdoControls allObjects]];
	*uniqueSet = goodControls;
	*theCmdoControls = myCmdoControls;
}


- (NSMutableString*) buildExecutionString
{
	NSString	*protoString = [mToolParser prototypeLine];
	NSMutableString	*cmdString = [NSMutableString stringWithString: protoString ];
	int			startP, stopP;
	NSMutableArray	*subsList = [NSMutableArray arrayWithCapacity: 50];
	
	[cmdString retain];

	for (int pass = 0; pass < 2; pass++)
	{
		// First build the list of match strings
		unsigned int	lengthOfString = [protoString length];
		unsigned int	i;
		
		for (i = 0; i < lengthOfString; i++)
		{
			unichar aChar = [protoString characterAtIndex: i];
			if (aChar == '[')
			{
				startP = i;
			}
			if (aChar == ']')
			{
				stopP = i;
				// Get the character match to save into the NSArray
				NSString	*matchToken = [protoString substringWithRange: NSMakeRange(startP, (stopP - startP + 1))];
				[subsList addObject: matchToken];
			}
		}

		// Now I have a list of substitions to get look for in the dictionary. If one doesn't exist, I just replace
		// with a NULL string.
		for (i = 0; i < [subsList count]; i++)
		{
			NSString	*matchStr = [subsList objectAtIndex: i];
			NSString	*newStr = [gSubstitutionDictionary objectForKey: matchStr];
			if (newStr == nil)
				newStr = @"";
			[cmdString replaceOccurrencesOfString: matchStr withString: newStr options: NSLiteralSearch range: NSMakeRange(0, [cmdString length])];
		}
		
		if (pass == 0)
		{
			protoString = cmdString;
		}
	}

	// And the final attack on the string is to remove any hanging "-" switches with nothing attached
	[cmdString replaceOccurrencesOfString: @" - " withString: @" " options: NSLiteralSearch range: NSMakeRange(0, [cmdString length])];

	// And a final cleanup: remove a trailing - for safety
	if ([cmdString characterAtIndex: [cmdString length] - 1] == '-')
	{
		[cmdString deleteCharactersInRange: NSMakeRange([cmdString length]-1, 1)];
	}
	
	// Now append the extra hand crafted line parameters and the I/O handling
	[cmdString appendFormat: @" %@ %@ %@ %@", [mAdditionalCommandLine string], [self stdinHandlingString],
												[self stdoutHandlingString], [self stderrHandlingString] ];

	return cmdString;
}

- (void) displayCommandLine
{
	NSMutableString *dispString = [self buildExecutionString];
	NSTextStorage	*textStore = [mOutputLine textStorage];
	[textStore replaceCharactersInRange: NSMakeRange(0, [textStore length]) withString: dispString];

	[dispString release];
}


// This method figures out which shell the user is using. This allows us to invoke the same shell
// they do so the syntax should all match up.
- (BOOL) findShell
{
	char **ePtr = environ;
	
	std::string	aStr;
	bool	done = false;
	BOOL	found = FALSE;

	do 
	{
		aStr = *ePtr;
		if (aStr.size() == 0)
			done = true;
		else 
		{
			if (aStr.find("SHELL=", 0) == 0)
			{
				mShellPathStr = [NSString stringWithCString: aStr.substr(6).c_str()];
				[mShellPathStr retain];
				found = TRUE;
				done = true;
			}
			ePtr++;
		}
	}while (!done && (*ePtr != nil));
	
	return (found);	// Bad karma day in Commando land if no shell found to execute in!
}


- (void) ioPopupActionHandler: (id) sender
{
	NSPopUpButton	*thePopup = sender;
	NSString		*selectedFileStr;
	
	[[self window] makeFirstResponder: self]; 	// Always reset first responder since the only cases where
												// FirstResponder is changed from the window happen when the user 
												// selects the UserTextField item, and then we explictly set it.
												// Leave editable fields as they are, in case the user swapped out and back
												// in though.
	int	theTag = [[thePopup selectedItem] tag];
	if (theTag >= kStderrPopupToOutput)
		mStderrTypeTag = theTag;
	else if (theTag >= kOutputPopupTerminal)
			mStdoutTypeTag = theTag;
		 else
		 	mStdinTypeTag = theTag;
		 

	switch (theTag)
	{
		// stdin handling section
		case kInputPopupTerminal:
		{
			[mInputTextView setEditable: FALSE];
			break;
		}

		case kInputPopupChooseFile:
		{
			[mInputTextView setEditable: FALSE];
			NSOpenPanel *thePanel = [NSOpenPanel openPanel];
			[thePanel retain];
			[thePanel setCanChooseDirectories: TRUE];
			[thePanel setCanChooseFiles: TRUE];
			[thePanel setAllowsMultipleSelection: FALSE];
			if ([thePanel runModalForDirectory: nil file: nil types: nil] == NSOKButton)
			{
				selectedFileStr = [[thePanel filenames] objectAtIndex: 0];
				[mInputTextView setString: selectedFileStr];
			}
			[thePanel release];
			break;
		}

		case kInputPopupTextField:
		{
			[mInputTextView setEditable: TRUE];
			[mInputTextView selectAll: self];
			[[self window] makeFirstResponder: mInputTextView];
			break;
		}

		// stdout handling section
		case kOutputPopupTerminal:
		{
			[mOutputTextView setEditable: FALSE];
			break;
		}

		case kOutputPopupDevNull:
		{
			[mOutputTextView setEditable: FALSE];
			[mOutputTextView setString: @"/dev/null"];
			break;
		}

		case kOutputPopupChooseFile:
		{
			[mOutputTextView setEditable: FALSE];

			NSSavePanel *savePanel = [NSSavePanel savePanel];
			[savePanel retain];
			if ([savePanel runModal] == NSFileHandlingPanelOKButton)
			{
				selectedFileStr = [savePanel filename];
				[mOutputTextView setString: selectedFileStr];
			}
			[savePanel release];
			break;
		}

		case kOutputPopupTextField:
		{
			[mOutputTextView setEditable: TRUE];
			[mOutputTextView selectAll: self];
			[[self window] makeFirstResponder: mOutputTextView];
			break;
		}

		case kOutputPopupPipe:
		{
			[mOutputTextView setEditable: FALSE];
			break;
		}


		// Stderr handling section
		case kStderrPopupToOutput:
		case kStderrPopupTerminal:
		{
			break;
		}

		case kStderrPopupDevNull:
		{
			[mErrorTextView setString: @"/dev/null"];
			break;
		}

		case kStderrPopupChooseFile:
		{
			NSSavePanel *errPanel = [NSSavePanel savePanel];
			[errPanel retain];
			if ([errPanel runModal] == NSFileHandlingPanelOKButton)
			{
				selectedFileStr = [errPanel filename];
				[mErrorTextView setString: selectedFileStr];
			}
			[errPanel release];
			break;
		}

		case kStderrPopupTextField:
		{
			[mErrorTextView setEditable: TRUE];
			[mErrorTextView selectAll: self];
			[[self window] makeFirstResponder: mErrorTextView];
			break;
		}
	}

	[self displayCommandLine];
	
}


- (NSString*) stdinHandlingString
{
	NSMutableString	*theString = nil;

	switch (mStdinTypeTag)
	{
		case kInputPopupTerminal:
			theString = [NSMutableString string];
			break;
		
		case kInputPopupChooseFile:		// Make sure we escape any spaces in the file name string
			theString = [NSMutableString stringWithFormat: @"<%@", [mInputTextView string] ];
			[theString replaceOccurrencesOfString: @" " withString: @"\\ " options: NSLiteralSearch range: NSMakeRange(0, [theString length])];
			break;

		case kInputPopupTextField:		// Assume the user knows how to quote and don't second guess
			theString = [NSMutableString stringWithFormat: @"<%@", [mInputTextView string] ];
			break;
	}
	
	return theString;
}


- (NSString*) stdoutHandlingString
{
	NSMutableString	*theString = nil;

	switch (mStdoutTypeTag)
	{
		case kOutputPopupTerminal:
			theString = [NSMutableString string];
			break;
		
		case kOutputPopupDevNull:
			theString = [NSMutableString stringWithString: @">/dev/null"];
			break;

		case kOutputPopupChooseFile:	// Make sure we escape any spaces in the file name string
			theString = [NSMutableString stringWithFormat: @">%@", [mOutputTextView string] ];
			[theString replaceOccurrencesOfString: @" " withString: @"\\ " options: NSLiteralSearch range: NSMakeRange(0, [theString length])];
			break;

		case kOutputPopupTextField:		// Assume the user knows how to quote and don't second guess
			theString = [NSMutableString stringWithFormat: @">%@", [mOutputTextView string] ];
			break;
		
		case kOutputPopupPipe:
			theString = [NSMutableString stringWithString: @"| "];
			break;
	}
	
	return theString;
}


- (NSString*) stderrHandlingString
{
	NSMutableString	*theString = nil;
	switch (mStderrTypeTag)
	{
		case kStderrPopupToOutput:
			if (mStdoutTypeTag == kOutputPopupTerminal)	// Special case if stdout && stderr go to terminal
				theString = [NSMutableString stringWithString: @""];
			else
				theString = [NSMutableString stringWithString: @"2>&1"];
			break;

		case kStderrPopupTerminal:
			theString = [NSMutableString string];
			break;

		case kStderrPopupDevNull:
			theString = [NSMutableString stringWithString: @"2>/dev/null"];
			break;

		case kStderrPopupChooseFile:		// Make sure we escape any spaces in the file name string
			theString = [NSMutableString stringWithFormat: @"2>%@", [mErrorTextView string] ];
			[theString replaceOccurrencesOfString: @" " withString: @"\\ " options: NSLiteralSearch range: NSMakeRange(0, [theString length])];
			break;

		case kStderrPopupTextField:			// Assume the user knows how to quote and don't second guess
			theString = [NSMutableString stringWithFormat: @"2>%@", [mErrorTextView string] ];
			break;
	}
	
	return theString;
}


- (void) textChangedNotificationHandler:(NSNotification *) theNotification
{
	[self displayCommandLine];
}


- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
	[[self window] makeFirstResponder: self];
}


void	signalCatcher(int signal)
{
//	int	result;
//	printf("pid = %d\n", gChildProcessID);
	switch (signal)
	{
		case SIGHUP:
		case SIGINT:
		case SIGKILL:
		case SIGQUIT:
		case SIGABRT:
		case SIGTERM:
			[gSubTask terminate];
//			result = kill(gChildProcessID, signal);
//			printf("Caught signal %d. kill result = %d, errno = %d\n", signal, result, errno);
			exit(1);
			break;
	}

}

@end

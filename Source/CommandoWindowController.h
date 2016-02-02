/* CommandoWindowController */
/*************************************************************************************************/
/* Copyright 2005 Shane D. Looker.                                                               */
/*                                                                                               */
/* This source code is being made available as free sample code as is. No warantee, express or   */
/* implied is made as to the quality or correctness of this code.                                */
/* This source code may be freely distributed as long as this copyright notice remains attached. */
/* Check http://www.MacCommando.com for updated source.                                          */
/*************************************************************************************************/

#import <Cocoa/Cocoa.h>
#import	<fstream>
#import "ToolParser.h"
#import "AssociatedTable.h"

enum 
{
	
	kInputPopupTerminal = 1000,
	kInputPopupChooseFile,
	kInputPopupTextField,

	kOutputPopupTerminal = 1100,
	kOutputPopupDevNull,
	kOutputPopupChooseFile,
	kOutputPopupTextField,
	kOutputPopupPipe,
	
	kStderrPopupToOutput = 1200,
	kStderrPopupTerminal,
	kStderrPopupDevNull,
	kStderrPopupChooseFile,
	kStderrPopupTextField
};


@interface CommandoWindowController : NSWindowController <NSTabViewDelegate>
{
    IBOutlet NSTextField	*mCommandName;
    IBOutlet NSTextView		*mOutputLine;
    IBOutlet NSTabView 		*myTabView;
    IBOutlet NSImageView 	*myImageTest;
    IBOutlet NSTextView		*mAdditionalCommandLine;
	IBOutlet NSTextView		*mInputTextView;		// 0< or just <
	IBOutlet NSTextView		*mOutputTextView;		// 1> or just >
	IBOutlet NSTextView		*mErrorTextView;		// 2>
	IBOutlet NSTextField	*mCreditBox;

	int		mStdinTypeTag;							// These tags identify how to handle stdio on the output line
	int		mStdoutTypeTag;
	int		mStderrTypeTag;
	
	ToolParser	*mToolParser;
//	NSString	*mCommandName;
	AssociatedTable	*mPanelDictionary;
	NSString	*mPrototypeLine;
	NSString	*mShellPathStr;
}


- (IBAction)doCancel:(id)sender;
- (IBAction)doDisplay:(id)sender;
- (IBAction)doExecute:(id)sender;
- (IBAction) ioPopupActionHandler: (id) sender;


- (void) awakeFromNib;

- (void) returnTerminalToFront;

- (void) buildInterfaceTabs;
- (void) fillControlTable: (AssociatedTable**) theCmdoControls andUniqueSet: (NSMutableSet**) uniqueSet fromTabControlList: (NSMutableArray*) tabControlList;

- (NSMutableString*) buildExecutionString;
- (void) displayCommandLine;

- (BOOL) findShell;

- (NSString*) stdinHandlingString;
- (NSString*) stdoutHandlingString;
- (NSString*) stderrHandlingString;

- (void) textChangedNotificationHandler:(NSNotification *) theNotification;
- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem;

@end

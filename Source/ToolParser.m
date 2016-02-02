/*************************************************************************************************//* Copyright 2005 Shane D. Looker.                                                               *//*                                                                                               *//* This source code is being made available as free sample code as is. No warantee, express or   *//* implied is made as to the quality or correctness of this code.                                *//* This source code may be freely distributed as long as this copyright notice remains attached. *//* Check http://www.MacCommando.com for updated source.                                          *//*************************************************************************************************/#import "ToolParser.h"@implementation ToolParser- (id) init{	mPanelDictionary = [[AssociatedTable alloc] init];	return [super init];}- (NSString*) prototypeLine{	return mPrototypeLine;}- (NSString*) toolSummaryLine{	return mToolSummaryLine;}- (NSString*) creditLine{	return mCreditLine;}- (AssociatedTable*) panelDictionary{	return mPanelDictionary;}- (BOOL) loadCommandDefinitionArgc: (int) argc Argv: (char**) argv {	std::string		tryString;	BOOL			theResult = FALSE;		for (int i = 0; (theResult == FALSE) && (i < 2); i++)	{		std::ifstream	*inStream = new std::ifstream();		if (i == 0)		// First pass. Try the machine /Library Preferences path first		{			tryString = "/";		}		else 		{			// Second pass, reset the lookupString for the User local Preferences			tryString = [NSHomeDirectory() cString];			tryString += "/";		}		tryString += kSearchPath;		tryString += argv[1];		tryString += ".cmdo";			inStream->open(tryString.c_str());		if (inStream->is_open() == true)		{	#if	USE_STREAMBUF		 // get length of file:		  inStream->seekg (0, std::ios::end);		  int len = inStream->tellg();		  inStream->seekg (0, std::ios::beg);		  // allocate memory:		  char *buffer = new char [len + 1];	  // read data as a block:	 		 inStream->read (buffer,len);	 		 buffer[len] = '\0';	 	 	  		// inStream->read(&buffer, 100*(int)1024);	  		std::stringstream	*a = new std::stringstream( std::string(buffer) );	  					[self readCommandPrototype: a]; // inStream];			[self readVersion: a];			[self readToolSummaryLine: a];			[self readCreditLine: a];			[self readPanels: a]; // inStream];	#else			[self readCommandPrototype: inStream];			[self readVersion: inStream];			[self readToolSummaryLine: inStream];			[self readCreditLine: inStream];			[self readPanels: inStream];	#endif			inStream->close();			theResult = TRUE;		}				delete inStream;		// Kill the stream if it opened or not.	}		// I never found the file, so return false	return theResult;	}#if USE_STREAMBUF- (void) readCommandPrototype: (std::stringstream*) inStream#else- (void) readCommandPrototype: (std::ifstream*) inStream#endif{	char	protoLine[1024];	inStream->getline(protoLine, sizeof(protoLine) - 1);	mPrototypeLine = [NSString stringWithCString: protoLine];	[mPrototypeLine retain];}#if USE_STREAMBUF- (void) readVersion: (std::stringstream*) inStream#else- (void) readVersion: (std::ifstream*) inStream#endif{	char protoLine[512];	inStream->getline(protoLine, sizeof(protoLine) - 1);}#if USE_STREAMBUF- (void) readToolSummaryLine: (std::stringstream*) inStream#else- (void) readToolSummaryLine: (std::ifstream*) inStream#endif{	char summary[2048];	inStream->getline(summary, sizeof(summary) - 1);	mToolSummaryLine = [NSString stringWithCString: summary];	[mToolSummaryLine retain];}#if USE_STREAMBUF- (void) readCreditLine: (std::stringstream*) inStream#else- (void) readCreditLine: (std::ifstream*) inStream#endif{	char protoLine[1024];	inStream->getline(protoLine, sizeof(protoLine) - 1);	mCreditLine = [NSString stringWithCString: protoLine];	[mCreditLine retain];}#if USE_STREAMBUF- (void) readPanels: (std::stringstream*) inStream#else- (void) readPanels: (std::ifstream*) inStream#endif{	BOOL	doneWithPanes = FALSE;	BOOL	doneWithThisPane = FALSE;		std::string	paneTag = "<pane ";	std::string endPaneTag = "</pane>";	do 	{		doneWithThisPane = FALSE;	// Now read a <pane ...> line		char	paneLine[1024];		inStream->getline(paneLine, sizeof(paneLine) - 1);		std::string	paneLineStr = paneLine;				int	findPost = paneLineStr.find(paneTag);		if (findPost != -1)		{						findPost += paneTag.size();			int endPost = paneLineStr.find(">");			std::string	paneNameStr = paneLineStr.substr(findPost, endPost - findPost);						NSString	*labelString = [NSString stringWithCString: paneNameStr.c_str()];			// The panelDictionary is an associative table with the tab name being the			// key and the object being an array of the control data arrays.			NSMutableArray	*tabControlList = [NSMutableArray arrayWithCapacity: 10];						do 			{				inStream->getline(paneLine, sizeof(paneLine) - 1);				paneLineStr = paneLine;				if (paneLineStr.find(endPaneTag) != -1)				{					doneWithThisPane = TRUE;					[mPanelDictionary setObject: tabControlList forKey: labelString];				//	NSLog([mPanelDictionary description]);				}				else 				{					// Parse this line to add to the pane					NSMutableArray *controlArray = [NSMutableArray arrayWithCapacity: 5];	// Space for 5 tabs before expanding					[self parseOptionLine:  &paneLineStr intoArray: controlArray]; //  intoTab: aTabView];					[tabControlList addObject: controlArray];				}			} while (!doneWithThisPane);		}		else			doneWithPanes = TRUE;			} while (!doneWithPanes);}- (void) parseOptionLine: (std::string*) line intoArray: (NSMutableArray*) controlArray //intoTab: (NSTabViewItem*) theTab{	// This routine will break up a string of elements separated by the delimiter "|" into 	// N fields. Each field will be entered into the controlArray.	// The last item is NOT delimited	// The standard format is: matchingItem in prototype, type of Control flag, flag subs field,	//							 control label, tool text		// I'm not using the standard cocoa string routine for this because I don't see a way to escape	// the split character to prevent splitting if I need the character in the string. (I could use	// an extended "character" like +|+, but that is cumbersome in the file. 			int	lastPost = 0;	int	fencePost;	// Put all the elements in the control array for later creation and insertion. Leave	// a space for the control which will be nil for now		// The first item in this array is a placeholder for the control which will be created later	[controlArray addObject: [NSObject new]];		do {		std::string	matchItem;				fencePost = line->find("|", lastPost);		BOOL	foundEscape;		do 		{			foundEscape = FALSE;			if ((fencePost > 0) && ((*line)[fencePost-1] == '\\'))	// Escaped |, look harder			{				line->erase(fencePost-1, 1);	// Remove the escape character and find the next |				fencePost = line->find("|", fencePost);				foundEscape = TRUE;			}		} while (foundEscape);		if (fencePost == -1)	// Didn't find another delimiter, so take to the end of the field line			matchItem = line->substr(lastPost);		else			matchItem = line->substr(lastPost, fencePost - lastPost);				lastPost = fencePost + 1;		// If fencePost == -1, we fall out so this is OK		[controlArray addObject: [NSString stringWithCString: matchItem.c_str()]];	} while (fencePost != -1);		}@end
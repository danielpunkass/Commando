/*************************************************************************************************/
/* Copyright 2005 Shane D. Looker.                                                               */
/*                                                                                               */
/* This source code is being made available as free sample code as is. No warantee, express or   */
/* implied is made as to the quality or correctness of this code.                                */
/* This source code may be freely distributed as long as this copyright notice remains attached. */
/* Check http://www.MacCommando.com for updated source.                                          */
/*************************************************************************************************/

#import <Cocoa/Cocoa.h>
#import <stdio.h>
#include <unistd.h>


extern char** environ;
int		gArgc;
char	**gArgv;

int main(int argc, const char *argv[])
{
	gArgc = (int) argc;
	gArgv = (char**) argv;
	
	return NSApplicationMain(argc, argv);
}

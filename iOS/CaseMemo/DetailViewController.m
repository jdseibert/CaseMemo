//
//  DetailViewController.m
//  CaseMemo
//
//  Created by Matthew Botos on 5/17/11.
//  Copyright 2011 Mavens Consulting, Inc. All rights reserved.
//

#import "DetailViewController.h"

#import "RootViewController.h"
#import "ZKSforce.h"
#import "FDCServerSwitchboard.h"
#import "CaseMemoAppDelegate.h"
#import "MBProgressHUD.h"
#import "NSData+Base64.h"
#import "DetailTable.h"

static const NSInteger OkButtonIndex = 1;
static NSString * const AudioAttachmentName = @"Audio Memo.caf";

@interface DetailViewController ()
@property (nonatomic, retain) UIPopoverController *popoverController;
- (void)configureView;
@end

@implementation DetailViewController
@synthesize recordButton = _recordButton;

@synthesize toolbar=_toolbar;

@synthesize detailItem=_detailItem;
@synthesize attachments=_attachments;

@synthesize detailTable = _detailTable;
@synthesize detailTableData = _detailTableData;

@synthesize attachmentsTable = _attachmentsTable;
@synthesize attachmentsLoadingIndicator = _attachmentsLoadingIndicator;
@synthesize attachmentsHeaderView = _attachmentsHeaderView;

@synthesize popoverController=_myPopoverController;

#pragma mark - Managing the detail item

/*
 When setting the detail item, update the view and dismiss the popover controller if it's showing.
 */
- (void)setDetailItem:(id)newDetailItem
{
    if (_detailItem != newDetailItem) {
        [_detailItem release];
        _detailItem = [newDetailItem retain];
        
        self.detailTableData = [[DetailTable alloc] init];
        self.detailTable.dataSource = self.detailTableData;
        [(DetailTable*)self.detailTable.dataSource setDetailItem:newDetailItem];
        
        [self.attachments removeAllObjects];
        
        // STEP 6 c - Use counter on Case to determine if there are Attachments to get
        // and if so, show the header with the loading indicator
        //
        // See CaseAttachmentCount_Test class in Salesforce for trigger and initialization
        
        if ([self.detailItem intValue:@"Attachment_Count__c"] > 0) {
            // STEP 5 c - Get Attachments for Case using SOQL query string
            // STEP 9 g - Only get audio Attachments
            NSString *queryString = [NSString stringWithFormat:@"Select Id, Name From Attachment Where ParentId = '%@' and Name = '%@'", 
                                     [self.detailItem fieldValue:@"Id"], AudioAttachmentName];
            [[FDCServerSwitchboard switchboard] query:queryString target:self selector:@selector(queryResult:error:context:) context:nil];
            hasAttachments = YES;
        } else {
            hasAttachments = NO;            
        }
    
        [self configureView];
    }

    if (self.popoverController != nil) {
        [self.popoverController dismissPopoverAnimated:YES];
    }        
}

- (void)queryResult:(ZKQueryResult *)result error:(NSError *)error context:(id)context
{
    if (result && !error)
    {
        // STEP 5 d - Store Attachment results and reload attachments table in view
        self.attachments = [[result records] mutableCopy];
        [self.attachmentsTable reloadData];
        
        // STEP 6 g - Stop loading indicator once Attachments are loaded
        // Will also hide indicator based on property set in .xib
        [self.attachmentsLoadingIndicator stopAnimating];
    }
    else if (error)
    {
        [CaseMemoAppDelegate errorWithError:error];
    }
}

- (void)configureView
{    
    [self.detailTable reloadData];
    [self.attachmentsTable reloadData];
    [self.view addSubview:self.recordButton];

    if (hasAttachments) {
        [self.attachmentsLoadingIndicator startAnimating];
    }
    
    // STEP 6 b - Hide loading indicator after data is loaded
    [MBProgressHUD hideHUDForView:self.view animated:YES];
}

// STEP 8 c - Create Salesforce object for Attachment
- (ZKSObject*) createAudioAttachment {
    ZKSObject *attachment = [ZKSObject withType:@"Attachment"];
    [attachment setFieldValue:AudioAttachmentName field:@"Name"];
    [attachment setFieldValue:[self.detailItem fieldValue:@"Id"] field:@"ParentId"];
    
    // Attachment body must be base64 encoded; use method provided by NSData+Base64 category
    NSData *soundData = [NSData dataWithContentsOfURL:audioURL];
    [attachment setFieldValue:[soundData base64EncodedString] field:@"Body"];
    
    return attachment;
}

// STEP 8 b - Save audio Attachment
- (void) saveAudioAttachment {
    ZKSObject *attachment = [self createAudioAttachment];
    [self.attachments addObject:attachment];
    hasAttachments = true;
    [self.detailItem setFieldValue:[NSNumber numberWithUnsignedInt:[self.attachments count]] field:@"Attachment_Count__c"];
    
    [self.attachmentsTable reloadData];
    
    // STEP 8 d - Create in Salesforce asynchronously
    [[FDCServerSwitchboard switchboard] create:[NSArray arrayWithObject:attachment] target:self selector:@selector(createResult:error:context:) context:attachment];
}

// STEP 8 e - Callback with result of Attachment creation in Salesforce
- (void)createResult:(NSArray *)results error:(NSError *)error context:(id)attachment
{
    if (results && !error)
    {
        // STEP 9 c - Set Id for newly created Attachment so we can query for Body
        NSString* attachmentId = [[results objectAtIndex:0] id]; 
        [attachment setId:attachmentId];
        NSLog(@"Attachment %@ saved to Salesforce", attachmentId);
    }
    else if (error)
    {
        [CaseMemoAppDelegate errorWithError:error];
    }
}

#pragma mark - Audio playback

// STEP 9 b - Load audio from Attachment Body if necessary
- (void) loadAudio:(ZKSObject *) attachment {
    if ([attachment fieldValue:@"Body"]) {
        [self playAudioAttachment:attachment];        
    } else {
        NSString *queryString = [NSString stringWithFormat:@"Select Body From Attachment Where Id = '%@'", [attachment Id]];
        [[FDCServerSwitchboard switchboard] query:queryString target:self selector:@selector(attachmentBodyQueryResult:error:context:) context:nil]; 
    }
}

// STEP 9 d - Process Attachment Body query result
- (void) attachmentBodyQueryResult:(ZKQueryResult *)result error:(NSError *)error context:(id)context
{
    if (result && !error)
    {
        ZKSObject *attachment = (ZKSObject*)[[result records] objectAtIndex:0];
        [self playAudioAttachment:attachment];
    }
    else if (error)
    {
        [MBProgressHUD hideHUDForView:self.view animated:YES];
    }
}

// STEP 9 e - Play audio from Attachment Body
- (void) playAudioAttachment:(ZKSObject *) attachment {
    // Decode body from base64
    NSData *audioData = [NSData dataFromBase64String:[attachment fieldValue:@"Body"]];
    
	if (audioData != nil) {
		NSError *error = nil;
		audioPlayer = [[AVAudioPlayer alloc] initWithData:audioData error:&error];
		if (error) {
			[CaseMemoAppDelegate errorWithError:error];
            return;
		}
        audioPlayer.delegate = self; // for detecting finish
        
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];	
		
		error = nil;
		[audioSession setActive: YES error: &error];
		if (error) {
			[CaseMemoAppDelegate errorWithError:error];
            return;
		}
		
		error = nil;
		[audioSession setCategory: AVAudioSessionCategoryPlayback error: &error];
		if (error) {
			[CaseMemoAppDelegate errorWithError:error];
            return;
		}
		
        [MBProgressHUD hideHUDForView:self.view animated:YES];
        
		[audioPlayer play];
	} else {
		[CaseMemoAppDelegate errorWithMessage:@"Attachment body is empty"];
	}
}

// STEP 9 f - Deselect table row when done playing
- (void)audioPlayerDidFinishPlaying:(AVAudioPlayer *)player successfully:(BOOL)flag {
    [self.attachmentsTable deselectRowAtIndexPath:audioIndexPath animated:YES];
}

#pragma mark - Audio recording

- (void) deleteSoundFile {
	NSError *error = nil;
	[[NSFileManager defaultManager] removeItemAtPath:[audioURL absoluteString] error:&error];	
	if (error != nil) {
		[CaseMemoAppDelegate errorWithError:error];
	}    
}

// STEP 7 c - Initialize audio
- (void) initializeAudio
{
    NSString *tempDir = NSTemporaryDirectory();	
    NSString *soundFilePath = [tempDir stringByAppendingString: @"sound.caf"];
	
    audioURL = [[NSURL alloc] initFileURLWithPath: soundFilePath];
	
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];	
    
	NSError *error = nil;
    [audioSession setActive: YES error: &error];	
	if (error != nil) {
		[CaseMemoAppDelegate errorWithError:error];
	}
}

// STEP 7 b - Record audio
- (IBAction)record:(id)sender {
    [self initializeAudio];
    
    [self startRecording];

    [self showRecordDialog];
}

// STEP 7 e - Show recording dialog
- (void) showRecordDialog {
	UIAlertView *dialog = [[UIAlertView alloc] initWithTitle:@"Recording" message:nil delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"Done", nil];
	[dialog show];
	[dialog release];    
}

// STEP 7 f - Respond to recording dialog Cancel or Done
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
    [self stopRecording];
    
    if (buttonIndex == OkButtonIndex) {
        // STEP 8 a - Replace TODO with actual save
        [self saveAudioAttachment];
    }
}

// STEP 7 d - Start recording
- (void) startRecording {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory: AVAudioSessionCategoryRecord error: &error];		
    if (error != nil) {
        [CaseMemoAppDelegate errorWithError:error];
    }
    
    // recording settings are very picky and undocumented
    // known good values: .caf file with AppleLossless, AppleIMA4, or uLaw		
    NSDictionary *recordSettings =		
    [[NSDictionary alloc] initWithObjectsAndKeys:		 
     [NSNumber numberWithFloat: 22050.0], AVSampleRateKey,		 
     [NSNumber numberWithInt: kAudioFormatULaw], AVFormatIDKey,		 
     [NSNumber numberWithInt: 1], AVNumberOfChannelsKey,		 
     [NSNumber numberWithInt: AVAudioQualityMedium], AVEncoderAudioQualityKey,		 
     nil];
    
    error = nil;		
    audioRecorder = [[AVAudioRecorder alloc] initWithURL:audioURL settings:recordSettings error:&error];
    if (error != nil) {
        // Error Domain=NSOSStatusErrorDomain Code=1718449215 means bad format
        [CaseMemoAppDelegate errorWithError:error];
    }	
	
    NSLog(@"Recording to %@", audioURL);
    
    [recordSettings release];		
    
    [audioRecorder prepareToRecord];		
    [audioRecorder record];
    
}

// STEP 7 g - Stop recording
- (void) stopRecording {
    NSLog(@"Recording stopped");
    
    [audioRecorder stop];		
    audioRecorder = nil;
    
    NSError *error = nil;		
    [[AVAudioSession sharedInstance] setActive: NO error:&error];		
    if (error != nil) {
        [CaseMemoAppDelegate errorWithError:error];
    }    
}

#pragma mark - Split view support

- (void)splitViewController:(UISplitViewController *)svc willHideViewController:(UIViewController *)aViewController withBarButtonItem:(UIBarButtonItem *)barButtonItem forPopoverController: (UIPopoverController *)pc
{
    // STEP 2 e - Change pop over button name; also change pop over title in MainWindow.xib
    barButtonItem.title = @"Cases";
    NSMutableArray *items = [[self.toolbar items] mutableCopy];
    [items insertObject:barButtonItem atIndex:0];
    [self.toolbar setItems:items animated:YES];
    [items release];
    self.popoverController = pc;
}

// Called when the view is shown again in the split view, invalidating the button and popover controller.
- (void)splitViewController:(UISplitViewController *)svc willShowViewController:(UIViewController *)aViewController invalidatingBarButtonItem:(UIBarButtonItem *)barButtonItem
{
    NSMutableArray *items = [[self.toolbar items] mutableCopy];
    [items removeObjectAtIndex:0];
    [self.toolbar setItems:items animated:YES];
    [items release];
    self.popoverController = nil;
}

// STEP 5 e - Render attachment table cells

#pragma mark - Attachments table data

- (UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIndentifer = @"AttachmentCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIndentifer];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIndentifer] autorelease];
    }
    
    ZKSObject *attachment = [self.attachments objectAtIndex:indexPath.row];
    cell.textLabel.text = [attachment fieldValue:@"Name"];
    
    return cell;
}

// STEP 6 f - Update table section count so table is visibile while loading
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return hasAttachments ? 1 : 0;
}

- (int) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.attachments count];
}


// STEP 6 e - Return custom Attachments header view with loading indicator

#pragma mark - Attachments table

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 24.0f;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return self.attachmentsHeaderView;
}

// Step 9 a - Load audio when Attachment is selected
- (void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ZKSObject *attachment = [self.attachments objectAtIndex:indexPath.row];
    audioIndexPath = indexPath; // save indexPath for deselect when done playing
    
    MBProgressHUD *progressHUD = [MBProgressHUD showHUDAddedTo:self.view animated:YES];
    progressHUD.labelText = @"Loading audio";
    
    [self loadAudio:attachment];
}

#pragma mark - View events

 // Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // STEP 6 d - Load Attachments header with loading indicator from DetailViewAttachmentsHeader.xib
    [[NSBundle mainBundle] loadNibNamed:@"DetailViewAttachmentsHeader" owner:self options:nil];
    
    self.attachmentsTable.backgroundView = [[[UIImageView alloc] init] autorelease];
    self.detailTable.backgroundView = [[[UIImageView alloc] init] autorelease];
    
    // prevent bad resizing and clipping when switching to landscape
    self.attachmentsTable.autoresizingMask = UIViewAutoresizingNone;
    self.detailTable.autoresizingMask = UIViewAutoresizingNone;
    
    [self.recordButton removeFromSuperview];
    
    // STEP 6 a - Show loading indicator while waiting for query callback
    [MBProgressHUD showHUDAddedTo:self.view animated:YES];
}

- (void)viewDidUnload
{
    [self setAttachmentsTable:nil];
    [self setAttachmentsHeaderView:nil];
    [self setRecordButton:nil];
    [self setDetailTable:nil];
	[super viewDidUnload];

	// Release any retained subviews of the main view.
	// e.g. self.myOutlet = nil;
	self.popoverController = nil;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillDisappear:(BOOL)animated
{
	[super viewWillDisappear:animated];
}

- (void)viewDidDisappear:(BOOL)animated
{
	[super viewDidDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}


#pragma mark - Memory management

- (void)didReceiveMemoryWarning
{
	// Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
	
	// Release any cached data, images, etc that aren't in use.
}

- (void)dealloc
{
    [_myPopoverController release];
    [_toolbar release];
    [_detailItem release];
    [_numberLabel release];
    [_subjectLabel release];
    [_descriptionLabel release];
    [_attachmentsTable release];
    [_attachmentsLoadingIndicator release];
    [_attachmentsHeaderView release];
    [_recordButton release];
	[audioRecorder release];
	[audioURL release];
    [_detailTable release];
    [_detailTableData release];
    [super dealloc];
}

@end

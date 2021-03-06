//
//  CaseMemoAppDelegate.m
//  CaseMemo
//
//  Created by Matthew Botos on 5/17/11.
//  Copyright 2011 Mavens Consulting, Inc. All rights reserved.
//

#import "CaseMemoAppDelegate.h"
#import "RootViewController.h"
#import "FDCOAuthViewController.h"
#import "FDCServerSwitchboard.h"
#import "GenericPassword.h"
#import "ZKSforce.h"
#import "DetailViewController.h"

// STEP 1 a - Consumer Key from Salesforce Setup > Develop > Remote Access
#define kSFOAuthConsumerKey @"3MVG9y6x0357HleejikYgTgKSQy7Ba8e7zCk_NwT6fye_OKUEmRjgZxgZ8OQCywvuw7WaW_g5VAJpijHWt9kC"

// STEP 3 a - Keychain label to save OAuth token
#define OAuthKeychainLabel @"OAuthRefreshToken"

@implementation CaseMemoAppDelegate


@synthesize window=_window;

@synthesize splitViewController=_splitViewController;

@synthesize rootViewController=_rootViewController;

@synthesize detailViewController=_detailViewController;

@synthesize oAuthViewController=_oAuthViewController;

@synthesize notificationData=_notificationData;

#pragma mark -
#pragma mark Error Handling

+ (void)error:(NSException*)exception {
	[self errorWithMessage:[exception reason]];
}

+ (void)errorWithError:(NSError*)error {
    NSString *message;
    
    if ([error userInfo] && [[error userInfo] valueForKey:@"faultstring"]) {
        message = [[error userInfo] valueForKey:@"faultstring"]; // detailed Salesforce error
    } else {
        message = [error localizedDescription];
    }
    
	[self errorWithMessage:message];
}

+ (void)errorWithMessage:(NSString*)message {
	NSLog(@"Error: %@", message);
	UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Error" message:message delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
    [self performSelectorOnMainThread:@selector(showAlert:) withObject:alert waitUntilDone:YES];
	[alert release];
}

+ (void) showAlert:(UIAlertView*)alert {
	[alert show];
}

#pragma mark -
#pragma mark App

- (void) didLogin {
    // STEP 10 a - Prompt to register for push notifications
    // Do after login so we can save device token to Salesforce 
#if !TARGET_IPHONE_SIMULATOR
    [[UIApplication sharedApplication] registerForRemoteNotificationTypes: 
	 (UIRemoteNotificationTypeAlert | UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound)];	
#endif
    
    // STEP 2 a - Load data after login
    [self.rootViewController loadData];
    
    // STEP 10 i - Go to Case in notification, if set
    if (self.notificationData) {
        [self showCaseInNotification];        
    }
}

// STEP 1 c - Handle OAuth login callback
- (void)loginOAuth:(FDCOAuthViewController *)oAuthViewController error:(NSError *)error
{
    if ([oAuthViewController accessToken] && !error)
    {
        NSLog(@"Logged in to Salesforce");
        [[FDCServerSwitchboard switchboard] setClientId:kSFOAuthConsumerKey];
        [[FDCServerSwitchboard switchboard] setApiUrlFromOAuthInstanceUrl:[oAuthViewController instanceUrl]];
        [[FDCServerSwitchboard switchboard] setSessionId:[oAuthViewController accessToken]];
        [[FDCServerSwitchboard switchboard] setOAuthRefreshToken:[oAuthViewController refreshToken]];
        
    	[self.splitViewController dismissModalViewControllerAnimated:YES];
        [self.oAuthViewController autorelease];
        
        // STEP 3 b - Save OAuth data after login
        [self saveOAuthData: oAuthViewController];
        
        [self didLogin];
    }
    else if (error)
    {
        [CaseMemoAppDelegate errorWithError:error];
    }
}

// STEP 3 c - Save OAuth data to Keychain
- (void) saveOAuthData: (FDCOAuthViewController *)oAuthViewController  {
    GenericPassword *genericPassword = [[GenericPassword alloc] initWithLabel:OAuthKeychainLabel accessGroup:nil];
    genericPassword.password = [oAuthViewController refreshToken];
    genericPassword.service = [oAuthViewController instanceUrl];
    
    NSError *error = nil;
    [genericPassword writeToKeychain:&error];
    if (error != nil) {
        NSLog(@"Error: %@", error);
        [CaseMemoAppDelegate errorWithError:error];
    }
    
    [genericPassword release];
}

#pragma mark -
#pragma mark AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // STEP 10 h - Get notification
    self.notificationData = [launchOptions objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
    
    [[FDCServerSwitchboard switchboard] setClientId:kSFOAuthConsumerKey];
    
    // STEP 3 d - Retrieve OAuth data from Keychain
    GenericPassword *genericPassword = [[GenericPassword alloc] initWithLabel:OAuthKeychainLabel accessGroup:nil];
    BOOL hasOAuthToken = genericPassword.password != @"";
    
    if (hasOAuthToken) {
        [[FDCServerSwitchboard switchboard] setOAuthRefreshToken:genericPassword.password];        
        [[FDCServerSwitchboard switchboard] setApiUrlFromOAuthInstanceUrl:genericPassword.service];        
        [self didLogin];
    } else {
        // STEP 1 b - Show OAuth login
        self.oAuthViewController = [[FDCOAuthViewController alloc] initWithTarget:self selector:@selector(loginOAuth:error:) clientId:kSFOAuthConsumerKey];
        self.oAuthViewController.modalPresentationStyle = UIModalPresentationFormSheet;
    }
    
    [genericPassword release];
    
    self.window.rootViewController = self.splitViewController;
    [self.window makeKeyAndVisible];
    
    // must occur after window is visible
    if (!hasOAuthToken) {
        [self.window.rootViewController presentModalViewController:self.oAuthViewController animated:YES];        
    }

    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    /*
     Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
     Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
     */
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    /*
     Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
     If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
     */
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    /*
     Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
     */
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    /*
     Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
     */
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    /*
     Called when the application is about to terminate.
     Save data if appropriate.
     See also applicationDidEnterBackground:.
     */
}

#pragma mark - Notifications

// STEP 10 b - On successful push notification registration, save device token for user
- (void)application:(UIApplication *)app didRegisterForRemoteNotificationsWithDeviceToken:(NSData *)deviceToken {
    // NSData contains token as <abc1 defd ...> - strip to just alphanumerics
    NSString *token = [NSString stringWithFormat:@"%@", deviceToken];
    token = [token stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"<>"]];

    ZKSObject *mobileDevice = [ZKSObject withType:@"Mobile_Device__c"];
    [mobileDevice setFieldValue:token field:@"Name"];
    // User__c will be set automatically by Salesforce trigger
    
    [[FDCServerSwitchboard switchboard] create:[NSArray arrayWithObject:mobileDevice] target:self selector:@selector(createResult:error:context:) context:nil];
}

// STEP 10 c - Callback with result of MobileDevice creation in Salesforce
- (void)createResult:(NSArray *)results error:(NSError *)error context:(id)context
{
    if (results && !error)
    {
        NSString* mobileDeviceId = [[results objectAtIndex:0] id]; 
        if ([mobileDeviceId length] > 0) {
            NSLog(@"Mobile Device %@ saved to Salesforce", mobileDeviceId);
        } else {
            NSLog(@"Duplicate Mobile Device ignored by Salesforce");
        }
    }
    else if (error)
    {
        [CaseMemoAppDelegate errorWithError:error];
    }
}

// STEP 10 d - Show error from unsuccessful push notification registration
- (void)application:(UIApplication *)application didFailToRegisterForRemoteNotificationsWithError:(NSError *)error {
	[CaseMemoAppDelegate errorWithError:error];
}

// STEP 10 e - Show notification alert if running
- (void)application:(UIApplication *)application didReceiveRemoteNotification:(NSDictionary *)userInfo {
    self.notificationData = userInfo;
	
    NSString *message = [ ( (NSDictionary*)[userInfo objectForKey:@"aps"] ) valueForKey:@"alert"];
    UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Case Closed" message:message delegate:self cancelButtonTitle:@"Dismiss" otherButtonTitles:@"View", nil];
    [alert show];    
    [alert release];
}

// STEP 10 f - Go to Case in notification
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if (buttonIndex == 1) {
        [self showCaseInNotification];
	}
}

- (void) showCaseInNotification {
    NSArray *caseIds = [self.notificationData objectForKey:@"caseIds"];
    self.detailViewController.detailItem = [self.rootViewController findCaseById:[caseIds objectAtIndex:0]];
}

- (void)dealloc
{
    [_window release];
    [_splitViewController release];
    [_rootViewController release];
    [_detailViewController release];
    [_notificationData release];
    [super dealloc];
}

@end

#import "Locative-Swift.h"
#import "CloudManager.h"
#import "SettingsViewController.h"
#import "Geofence.h"
#import "GeofencesViewController.h"
#import "HttpRequest.h"
#import "UIDevice+Locative.h"

@import AFNetworking;
@import INTULocationManager;
@import iOS_GPX_Framework;
@import MessageUI;
@import OnePasswordExtension;
@import ObjectiveRecord;
@import PSTAlertController;
@import SVProgressHUD;

@interface SettingsViewController () <UITextFieldDelegate, MFMailComposeViewControllerDelegate>

@property (nonatomic, weak) IBOutlet UITextField *httpUrlTextField;
@property (nonatomic, weak) IBOutlet UISegmentedControl *httpMethodSegmentedControl;

@property (nonatomic, weak) IBOutlet UISwitch *httpBasicAuthSwitch;
@property (nonatomic, weak) IBOutlet UITextField *httpBasicAuthUsernameTextField;
@property (nonatomic, weak) IBOutlet UITextField *httpBasicAuthPasswordTextField;

@property (nonatomic, weak) IBOutlet UISwitch *notifyOnSuccessSwitch;
@property (nonatomic, weak) IBOutlet UISwitch *notifyOnFailureSwitch;
@property (nonatomic, weak) IBOutlet UISwitch *soundOnNotificationSwitch;

@property (nonatomic, weak) IBOutlet UITextField *myGfUsername;
@property (nonatomic, weak) IBOutlet UITextField *myGfPassword;
@property (nonatomic, weak) IBOutlet UIButton *passwordManagerButton;
@property (nonatomic, strong) IBOutlet NSLayoutConstraint *passwordManagerButtonShowConstraint;

@property (nonatomic, weak) IBOutlet UIButton *myGfLoginButton;
@property (nonatomic, weak) IBOutlet UIButton *myGfCreateAccountButton;
@property (nonatomic, weak) IBOutlet UIButton *myGfLostPwButton;

@property (nonatomic, strong) Settings *settings;
@property (nonatomic, weak) AppDelegate *appDelegate;

@end

@implementation SettingsViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    
    self.appDelegate = (AppDelegate *)[[UIApplication sharedApplication] delegate];
    self.settings = self.appDelegate.settings;
	
	// show/hide password manager button next to the password text field
	if ([[OnePasswordExtension sharedExtension] isAppExtensionAvailable]) {
		NSURL *resourceBundleUrl = [[NSBundle bundleForClass:OnePasswordExtension.class] URLForResource:@"OnePasswordExtensionResources" withExtension:@"bundle"];
		NSBundle *resourceBundle = [NSBundle bundleWithURL:resourceBundleUrl];
		[self.passwordManagerButton setImage:[UIImage imageNamed:@"onepassword-button" inBundle:resourceBundle compatibleWithTraitCollection:nil] forState:UIControlStateNormal];
		self.passwordManagerButtonShowConstraint.active = YES;
	} else {
		[self.passwordManagerButton setImage:nil forState:UIControlStateNormal];
		self.passwordManagerButtonShowConstraint.active = NO;
	}
	
    /*
     Drawer Menu Shadow
     */
    self.parentViewController.view.layer.shadowOpacity = 0.75f;
    self.parentViewController.view.layer.shadowRadius = 10.0f;
    self.parentViewController.view.layer.shadowColor = [UIColor blackColor].CGColor;
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    [self.httpUrlTextField setText:([[[self.settings globalUrl] absoluteString] length] > 0)?[[self.settings globalUrl] absoluteString]:nil];
    [self.httpMethodSegmentedControl setSelectedSegmentIndex:[[self.settings globalHttpMethod] integerValue]];
    
    self.httpBasicAuthSwitch.on = [self.settings httpBasicAuthEnabled].boolValue;
    [self.httpBasicAuthUsernameTextField setEnabled:self.httpBasicAuthSwitch.on];
    [self.httpBasicAuthPasswordTextField setEnabled:self.httpBasicAuthSwitch.on];
    [self.httpBasicAuthUsernameTextField setText:([[self.settings httpBasicAuthUsername] length] > 0)?[self.settings httpBasicAuthUsername]:nil];
    [self.httpBasicAuthPasswordTextField setText:([[self.settings httpBasicAuthPassword] length] > 0)?[self.settings httpBasicAuthPassword]:nil];
    
    self.notifyOnSuccessSwitch.on = [self.settings notifyOnSuccess].boolValue;
    self.notifyOnFailureSwitch.on = [self.settings notifyOnFailure].boolValue;
    self.soundOnNotificationSwitch.on = [self.settings soundOnNotification].boolValue;

    [[self.appDelegate cloudManager] validateSessionWithCallback:^(BOOL valid) {
        if (valid) {
            self.myGfCreateAccountButton.hidden = YES;
            self.myGfLostPwButton.hidden = YES;
            self.myGfLoginButton.hidden = YES;
        }
        [[self tableView] reloadData];
    }];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    
    UIUserNotificationType types = (UIUserNotificationTypeBadge | UIUserNotificationTypeSound | UIUserNotificationTypeAlert);
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
    [[UIApplication sharedApplication] registerForRemoteNotifications];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - UITableViewDelegate
- (CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 2) {
        if (indexPath.row >= 0 && indexPath.row < 5) {
            if ([[self.appDelegate.settings apiToken] length] == 0) {
                return [super tableView:tableView heightForRowAtIndexPath:indexPath];
            } else {
                return 0.0f;
            }
        } else if (indexPath.row >= 5) {
            if ([[self.appDelegate.settings apiToken] length] == 0) {
                return 0.0f;
            } else {
                return [super tableView:tableView heightForRowAtIndexPath:indexPath];
            }
        }
    }
    
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}

#pragma mark - TextField Delegate
- (BOOL) textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Helpers
- (AFSecurityPolicy *) commonPolicy {
    AFSecurityPolicy *policy = [AFSecurityPolicy policyWithPinningMode:AFSSLPinningModeNone];
    [policy setAllowInvalidCertificates:YES];
    [policy setValidatesDomainName:NO];
    return policy;
}

#pragma mark - IBActions
- (IBAction)saveSettings:(id)sender {
    // Normalize URL if necessary
    if ([[self.httpUrlTextField text] length] > 0) {
        if([[[self.httpUrlTextField text] lowercaseString] hasPrefix:@"http://"] || [[[self.httpUrlTextField text] lowercaseString] hasPrefix:@"https://"]) {
            [self.settings setGlobalUrl:[NSURL URLWithString:[self.httpUrlTextField text]]];
        } else {
            [self.settings setGlobalUrl:[NSURL URLWithString:[@"http://" stringByAppendingString:[self.httpUrlTextField text]]]];
        }
    } else {
        [self.settings setGlobalUrl:nil];
    }
    
    [self.settings setHttpBasicAuthUsername:[self.httpBasicAuthUsernameTextField text]];
    [self.settings setHttpBasicAuthPassword:[self.httpBasicAuthPasswordTextField text]];
    
    [self.settings setGlobalHttpMethod:@([self.httpMethodSegmentedControl selectedSegmentIndex])];
    [self.settings setNotifyOnSuccess:@(self.notifyOnSuccessSwitch.on)];
    [self.settings setNotifyOnFailure:@(self.notifyOnFailureSwitch.on)];
    [self.settings setSoundOnNotification:@(self.soundOnNotificationSwitch.on)];
    
    [self.settings persist];

    [(UITabBarController *)[[UIApplication sharedApplication].delegate.window rootViewController] setSelectedIndex:0];
}

- (IBAction)toggleHttpBasicAuth:(id)sender {
    [_settings setHttpBasicAuthEnabled:[NSNumber numberWithBool:_httpBasicAuthSwitch.on]];
    [_httpBasicAuthUsernameTextField setEnabled:_httpBasicAuthSwitch.on];
    [_httpBasicAuthPasswordTextField setEnabled:_httpBasicAuthSwitch.on];
}

- (IBAction) toogleNotificationSettings:(id)sender {
    [_settings setNotifyOnSuccess:[NSNumber numberWithBool:_notifyOnSuccessSwitch.on]];
    [_settings setNotifyOnFailure:[NSNumber numberWithBool:_notifyOnFailureSwitch.on]];
    [_settings setSoundOnNotification:[NSNumber numberWithBool:_soundOnNotificationSwitch.on]];
}

- (IBAction) sendTestRequest:(id)sender {
    [[INTULocationManager sharedInstance] requestLocationWithDesiredAccuracy:INTULocationAccuracyRoom
                                                                     timeout:10.0
                                                        delayUntilAuthorized:YES
                                                                       block:
     ^(CLLocation *currentLocation, INTULocationAccuracy achievedAccuracy, INTULocationStatus status) {
         NSString *url = [self.httpUrlTextField text];
         NSString *eventId = [[NSUUID UUID] UUIDString];
         NSString *deviceId = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
         NSDate *timestamp = [NSDate date];
         
         NSDictionary *parameters = @{@"id":eventId,
                                      @"trigger":@"test",
                                      @"device":deviceId,
                                      @"device_type": [[UIDevice currentDevice] model],
                                      @"device_model": [UIDevice locative_deviceModel],
                                      @"latitude":currentLocation?[NSNumber numberWithFloat:currentLocation.coordinate.latitude]:@123.00,
                                      @"longitude":currentLocation?[NSNumber numberWithFloat:currentLocation.coordinate.longitude]:@123.0f,
                                      @"timestamp": [NSString stringWithFormat:@"%f", [timestamp timeIntervalSince1970]]};
         
         HttpRequest *httpRequest = [HttpRequest create];
         httpRequest.url = url;
         httpRequest.method = ([self.httpMethodSegmentedControl selectedSegmentIndex] == 0)?@"POST":@"GET";
         httpRequest.parameters = parameters;
         httpRequest.eventType = [NSNumber numberWithInt:0];
         httpRequest.timestamp = timestamp;
         httpRequest.uuid = [[NSUUID UUID] UUIDString];
         
         if ([self.settings httpBasicAuthEnabled]) {
             httpRequest.httpAuth = [NSNumber numberWithBool:YES];
             httpRequest.httpAuthUsername = [self.settings httpBasicAuthUsername];
             httpRequest.httpAuthPassword = [self.settings httpBasicAuthPassword];
         }
         
         [httpRequest save];
         [self.appDelegate.requestManager flushWithCompletion:nil];
    }];
    
    PSTAlertController *controller = [PSTAlertController alertControllerWithTitle:NSLocalizedString(@"Note", nil)
                                                                          message:NSLocalizedString(@"A Test-Request has been sent. The result will be displayed as soon as it's succeeded / failed.", nil)
                                                                   preferredStyle:PSTAlertControllerStyleAlert];
    [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:PSTAlertActionStyleDefault handler:nil]];
    [controller showWithSender:sender controller:self animated:YES completion:nil];
}

- (IBAction)passwordManagerButtonTapped:(id)sender {
	[[OnePasswordExtension sharedExtension] findLoginForURLString:@"https://my.locative.io" forViewController:self sender:sender completion:^(NSDictionary *loginDictionary, NSError *error) {
		if (loginDictionary.count == 0) {
			if (error.code != AppExtensionErrorCodeCancelledByUser) {
				NSLog(@"Error invoking 1Password App Extension for find login: %@", error);
			}
			return;
		}
		
		self.myGfUsername.text = loginDictionary[AppExtensionUsernameKey];
		self.myGfPassword.text = loginDictionary[AppExtensionPasswordKey];
		[self loginToAccount:self.myGfLoginButton];
	}];
}

- (IBAction) loginToAccount:(id)sender {
    [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeClear];
    
    CloudCredentials *credentials = [[CloudCredentials alloc] initWithUsername:[self.myGfUsername text]
                                                                         email:nil
                                                                      password:[self.myGfPassword text]];
    
    [[self.appDelegate cloudManager] loginToAccountWithCredentials:credentials onFinish:^(NSError *error, NSString *sessionId) {
        
        [SVProgressHUD dismiss];
        
        self.myGfCreateAccountButton.hidden = !error;
        self.myGfLostPwButton.hidden = !error;
        self.myGfLoginButton.hidden = !error;
        
        if (!error) {
            [self.appDelegate.settings setApiToken:sessionId];
            [self.appDelegate.settings persist];
            [[self tableView] reloadData];
        }
        
        PSTAlertController *controller = [PSTAlertController alertControllerWithTitle:error ? NSLocalizedString(@"Error", nil) : NSLocalizedString(@"Success", nil)
                                                                              message:error ? NSLocalizedString(@"There has been a problem with your login, please try again!", nil) : NSLocalizedString(@"Login successful! Your triggered geofences will now be visible in you Account at http://my.locative.io!", nil)
                                                                       preferredStyle:PSTAlertControllerStyleAlert];
        [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:PSTAlertActionStyleDefault handler:nil]];
        [controller showWithSender:sender controller:self animated:YES completion:nil];
    }];
}

- (IBAction) recoverMyGfPassword:(id)sender {
    PSTAlertController *controller = [PSTAlertController alertControllerWithTitle:NSLocalizedString(@"Note", nil)
                                                                          message:NSLocalizedString(@"This will open up Safari and lead you to the password recovery website. Sure?", nil)
                                                                   preferredStyle:PSTAlertControllerStyleAlert];
    [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"No", nil) style:PSTAlertActionStyleDefault handler:nil]];
    [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"Yes", nil) style:PSTAlertActionStyleDefault handler:^(PSTAlertAction *action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"http://my.locative.io/youforgot"]];
    }]];
    [controller showWithSender:sender controller:self animated:YES completion:nil];
}

- (IBAction) logout:(id)sender {
    [self.appDelegate.settings removeApiToken];
    
    self.myGfCreateAccountButton.hidden = NO;
    self.myGfLostPwButton.hidden = NO;
    self.myGfLoginButton.hidden = NO;
    [[self tableView] reloadData];
}

- (IBAction) exportAsGpx:(id)sender {
    PSTAlertController *controller = [PSTAlertController alertControllerWithTitle:NSLocalizedString(@"Note", nil)
                                                                          message:NSLocalizedString(@"Your Geofences (no iBeacons) will be exported as an ordinary GPX file, only location and UUID/Name as well as Description will be exported. Custom settings like radius and URLs will fall back to default.", nil)
                                                                   preferredStyle:PSTAlertControllerStyleAlert];
    [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:PSTAlertActionStyleDefault handler:^(PSTAlertAction *action) {
        [self performExportGpx:sender];
    }]];
    [controller showWithSender:sender controller:self animated:YES completion:nil];
}

- (void) performExportGpx:(id)sender {
    [SVProgressHUD showWithMaskType:SVProgressHUDMaskTypeClear];
    
    GPXRoot *root = [GPXRoot rootWithCreator:@"Locative"];
    __block NSString *gpx = @"";
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSArray *geofences = [Geofence all];
        for (Geofence *geofence in geofences) {
            if ([geofence.type intValue] == GeofenceTypeGeofence) {
                GPXWaypoint *waypoint = [GPXWaypoint waypointWithLatitude:[geofence.latitude floatValue] longitude:[geofence.longitude floatValue]];
                waypoint.name = ([geofence.customId length] > 0)?geofence.customId:geofence.uuid;
                waypoint.comment = geofence.name;
                [root addWaypoint:waypoint];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            gpx = [root gpx];
            [SVProgressHUD dismiss];
            [self shareGpx:gpx sender:sender];
        });
    });
}

- (NSString *)temporaryFilePath {
    return [[NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]
            stringByAppendingPathComponent:@"Geofences.gpx"];
}

- (void)shareGpx:(NSString *)gpx sender:(UIButton *)button {
    if ([[gpx dataUsingEncoding:NSUTF8StringEncoding] writeToFile:[self temporaryFilePath] atomically:YES]) {
        NSString *path = [self temporaryFilePath];
        UIDocumentInteractionController *interactionController =
        [UIDocumentInteractionController interactionControllerWithURL:[NSURL fileURLWithPath:path]];
        [interactionController presentOptionsMenuFromRect:button.frame inView:self.view animated:YES];
    } else {
        PSTAlertController *controller = [PSTAlertController alertControllerWithTitle:NSLocalizedString(@"Error", nil)
                                                                              message:NSLocalizedString(@"Something went wrong when exporting your Geofences.", nil)
                                                                       preferredStyle:PSTAlertControllerStyleAlert];
        [controller addAction:[PSTAlertAction actionWithTitle:NSLocalizedString(@"OK", nil) style:PSTAlertActionStyleDefault handler:nil]];
        [controller showWithSender:nil controller:self animated:YES completion:nil];
    }
}

#pragma mark - MailComposeViewController Delegate
- (void) mailComposeController:(MFMailComposeViewController *)controller
           didFinishWithResult:(MFMailComposeResult)result
                         error:(NSError *)error {
    [controller dismissViewControllerAnimated:YES completion:nil];
}

@end

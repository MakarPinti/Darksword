#import "ADSRootViewController.h"
#import "ADSDarkEngine.h"
#import "sandbox_escape.h"
#import "kutils.h"
#import "vnode.h"
#include <dirent.h>
#include <limits.h>
#include <unistd.h>
#include <sys/stat.h>

static NSString * const kADSStandoff2BundleID = @"com.axlebolt.standoff2";
static NSString * const kADSCachedStandoff2PlistKey = @"ADS.cachedStandoff2InfoPlist";

static UIColor *ADSColor(CGFloat white, CGFloat alpha) {
    return [UIColor colorWithWhite:white alpha:alpha];
}

@interface ADSBackgroundView : UIView
@property (nonatomic, assign) CGFloat phase;
@end

@implementation ADSBackgroundView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = ADSColor(0.024, 1);
        self.userInteractionEnabled = NO;
        CADisplayLink *link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
        [link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    }
    return self;
}

- (void)tick {
    self.phase += 0.006;
    [self setNeedsDisplay];
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();

    NSArray *colors = @[
        (__bridge id)ADSColor(0.020, 1).CGColor,
        (__bridge id)ADSColor(0.042, 1).CGColor,
        (__bridge id)ADSColor(0.026, 1).CGColor
    ];
    CGFloat locations[] = {0.0, 0.50, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColors(space, (__bridge CFArrayRef)colors, locations);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(rect.size.width, rect.size.height), 0);
    CGGradientRelease(gradient);

    CGFloat sweep = fmod(self.phase * 32.0, rect.size.height + 120.0) - 60.0;
    CGContextSetLineWidth(context, 1.0);
    for (NSInteger i = -2; i < 15; i++) {
        CGFloat y = sweep + i * 68.0;
        CGContextSetStrokeColorWithColor(context, ADSColor(1, i % 4 == 0 ? 0.020 : 0.010).CGColor);
        CGContextMoveToPoint(context, -20, y);
        CGContextAddLineToPoint(context, rect.size.width + 20, y - 14.0);
        CGContextStrokePath(context);
    }

    CGFloat beamX = fmod(self.phase * 40.0, rect.size.width + 220.0) - 110.0;
    NSArray *beamColors = @[
        (__bridge id)ADSColor(1, 0.0).CGColor,
        (__bridge id)ADSColor(1, 0.024).CGColor,
        (__bridge id)ADSColor(1, 0.0).CGColor
    ];
    CGFloat beamLocations[] = {0.0, 0.50, 1.0};
    CGGradientRef beam = CGGradientCreateWithColors(space, (__bridge CFArrayRef)beamColors, beamLocations);
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, beamX, 0);
    CGContextRotateCTM(context, -0.10);
    CGContextDrawLinearGradient(context, beam, CGPointMake(0, 0), CGPointMake(140, 0), 0);
    CGContextRestoreGState(context);
    CGGradientRelease(beam);

    CGColorSpaceRelease(space);
}

@end

@interface ADSRootViewController ()
@property (nonatomic, strong) NSString *foundGamePath;
@property (nonatomic, strong) UILabel *headlineLabel;
@property (nonatomic, strong) UITextView *logView;
@property (nonatomic, strong) UIView *progressTrack;
@property (nonatomic, strong) UIView *progressFill;
@property (nonatomic, strong) NSLayoutConstraint *progressFillWidth;
@property (nonatomic, strong) UILabel *percentLabel;
@property (nonatomic, strong) UIButton *runButton;
@property (nonatomic, strong) ADSDarkEngine *darkEngine;
@property (nonatomic, assign) BOOL running;
@property (nonatomic, assign) BOOL finished;
@end

@implementation ADSRootViewController

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = ADSColor(0.024, 1);
    self.darkEngine = [ADSDarkEngine new];

    ADSBackgroundView *background = [ADSBackgroundView new];
    background.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:background];
    [NSLayoutConstraint activateConstraints:@[
        [background.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [background.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [background.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [background.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    UIStackView *root = [UIStackView new];
    root.axis = UILayoutConstraintAxisVertical;
    root.alignment = UIStackViewAlignmentFill;
    root.spacing = 12;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];

    [root addArrangedSubview:[self headerView]];
    [root addArrangedSubview:[self panelView]];

    UIButton *telegram = [self buttonWithTitle:@"Telegram" primary:NO];
    [telegram addTarget:self action:@selector(openTelegram) forControlEvents:UIControlEventTouchUpInside];
    [telegram addTarget:self action:@selector(buttonPressDown:) forControlEvents:UIControlEventTouchDown];
    [telegram addTarget:self action:@selector(buttonPressUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [root addArrangedSubview:telegram];

    self.runButton = [self buttonWithTitle:@"Run Preview" primary:YES];
    [self.runButton addTarget:self action:@selector(runSequence) forControlEvents:UIControlEventTouchUpInside];
    [self.runButton addTarget:self action:@selector(buttonPressDown:) forControlEvents:UIControlEventTouchDown];
    [self.runButton addTarget:self action:@selector(buttonPressUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [root addArrangedSubview:self.runButton];

    UILayoutGuide *guide = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor constant:22],
        [root.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-22],
        [root.centerYAnchor constraintEqualToAnchor:guide.centerYAnchor constant:-4],
        [root.topAnchor constraintGreaterThanOrEqualToAnchor:guide.topAnchor constant:18],
        [root.bottomAnchor constraintLessThanOrEqualToAnchor:guide.bottomAnchor constant:-18],
        [telegram.heightAnchor constraintEqualToConstant:64],
        [self.runButton.heightAnchor constraintEqualToConstant:64],
    ]];

    UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [copyBtn setTitle:@"\U0001F4CB" forState:UIControlStateNormal];
    copyBtn.titleLabel.font = [UIFont systemFontOfSize:22];
    copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
    copyBtn.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    copyBtn.layer.cornerRadius = 22;
    [copyBtn addTarget:self action:@selector(copyLogs) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:copyBtn];
    [NSLayoutConstraint activateConstraints:@[
        [copyBtn.widthAnchor constraintEqualToConstant:44],
        [copyBtn.heightAnchor constraintEqualToConstant:44],
        [copyBtn.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor constant:-16],
        [copyBtn.topAnchor constraintEqualToAnchor:guide.topAnchor constant:8],
    ]];

    [self resetInterface];
    [self animateIn:root];
}

- (UIView *)headerView {
    UIView *view = [UIView new];
    [view.heightAnchor constraintEqualToConstant:86].active = YES;

    UILabel *title = [self label:@"DarkSword" size:36 weight:UIFontWeightSemibold alpha:0.96 alignment:NSTextAlignmentCenter];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.adjustsFontSizeToFitWidth = YES;
    title.minimumScaleFactor = 0.78;
    [view addSubview:title];

    UILabel *subtitle = [self label:@"Exploit Chain" size:15 weight:UIFontWeightRegular alpha:0.42 alignment:NSTextAlignmentCenter];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:subtitle];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [title.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [title.bottomAnchor constraintEqualToAnchor:view.centerYAnchor constant:2],
        [subtitle.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [subtitle.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:5],
    ]];

    return view;
}

- (UIView *)panelView {
    UIView *panel = [UIView new];
    panel.backgroundColor = ADSColor(0.100, 0.94);
    panel.layer.cornerRadius = 24;
    panel.layer.borderWidth = 1;
    panel.layer.borderColor = ADSColor(1, 0.075).CGColor;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.20;
    panel.layer.shadowRadius = 24;
    panel.layer.shadowOffset = CGSizeMake(0, 12);
    [panel.heightAnchor constraintEqualToConstant:468].active = YES;

    UIStackView *content = [UIStackView new];
    content.axis = UILayoutConstraintAxisVertical;
    content.spacing = 16;
    content.translatesAutoresizingMaskIntoConstraints = NO;
    [panel addSubview:content];

    self.headlineLabel = [self label:@"Ready" size:28 weight:UIFontWeightSemibold alpha:0.94 alignment:NSTextAlignmentCenter];
    self.headlineLabel.adjustsFontSizeToFitWidth = YES;
    self.headlineLabel.minimumScaleFactor = 0.78;
    [content addArrangedSubview:self.headlineLabel];

    UIView *logContainer = [UIView new];
    logContainer.backgroundColor = ADSColor(0.058, 0.50);
    logContainer.layer.cornerRadius = 18;
    logContainer.layer.borderWidth = 1;
    logContainer.layer.borderColor = ADSColor(1, 0.045).CGColor;
    [content addArrangedSubview:logContainer];

    self.logView = [UITextView new];
    self.logView.translatesAutoresizingMaskIntoConstraints = NO;
    self.logView.backgroundColor = UIColor.clearColor;
    self.logView.textColor = ADSColor(1, 0.70);
    self.logView.font = [UIFont monospacedSystemFontOfSize:12.0 weight:UIFontWeightRegular];
    self.logView.editable = NO;
    self.logView.selectable = NO;
    self.logView.scrollEnabled = YES;
    self.logView.textAlignment = NSTextAlignmentLeft;
    self.logView.showsVerticalScrollIndicator = YES;
    self.logView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
    self.logView.textContainerInset = UIEdgeInsetsMake(22, 20, 22, 20);
    self.logView.textContainer.lineFragmentPadding = 0;
    [logContainer addSubview:self.logView];

    UIStackView *progressRow = [UIStackView new];
    progressRow.axis = UILayoutConstraintAxisHorizontal;
    progressRow.alignment = UIStackViewAlignmentCenter;
    progressRow.spacing = 12;
    [content addArrangedSubview:progressRow];

    self.progressTrack = [UIView new];
    self.progressTrack.backgroundColor = ADSColor(1, 0.070);
    self.progressTrack.layer.cornerRadius = 3;
    self.progressTrack.clipsToBounds = YES;
    [progressRow addArrangedSubview:self.progressTrack];

    self.progressFill = [UIView new];
    self.progressFill.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressFill.backgroundColor = ADSColor(0.86, 1);
    self.progressFill.layer.cornerRadius = 3;
    [self.progressTrack addSubview:self.progressFill];

    self.percentLabel = [self label:@"0%" size:14 weight:UIFontWeightMedium alpha:0.62 alignment:NSTextAlignmentRight];
    [self.percentLabel.widthAnchor constraintEqualToConstant:46].active = YES;
    [progressRow addArrangedSubview:self.percentLabel];

    [NSLayoutConstraint activateConstraints:@[
        [content.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-20],
        [content.topAnchor constraintEqualToAnchor:panel.topAnchor constant:22],
        [content.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-20],
        [logContainer.heightAnchor constraintEqualToConstant:340],
        [self.logView.leadingAnchor constraintEqualToAnchor:logContainer.leadingAnchor],
        [self.logView.trailingAnchor constraintEqualToAnchor:logContainer.trailingAnchor],
        [self.logView.topAnchor constraintEqualToAnchor:logContainer.topAnchor],
        [self.logView.bottomAnchor constraintEqualToAnchor:logContainer.bottomAnchor],
        [self.progressTrack.heightAnchor constraintEqualToConstant:6],
        [self.progressFill.leadingAnchor constraintEqualToAnchor:self.progressTrack.leadingAnchor],
        [self.progressFill.topAnchor constraintEqualToAnchor:self.progressTrack.topAnchor],
        [self.progressFill.bottomAnchor constraintEqualToAnchor:self.progressTrack.bottomAnchor],
    ]];

    self.progressFillWidth = [self.progressFill.widthAnchor constraintEqualToConstant:0];
    self.progressFillWidth.active = YES;

    return panel;
}

- (UIButton *)buttonWithTitle:(NSString *)title primary:(BOOL)primary {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:ADSColor(0.94, 1) forState:UIControlStateNormal];
    [button setTitleColor:ADSColor(1, 0.36) forState:UIControlStateDisabled];
    button.titleLabel.font = [UIFont systemFontOfSize:21 weight:UIFontWeightSemibold];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    button.titleLabel.minimumScaleFactor = 0.75;
    button.backgroundColor = ADSColor(0.118, 0.96);
    button.layer.cornerRadius = 18;
    button.layer.borderWidth = 1;
    button.layer.borderColor = ADSColor(1, primary ? 0.100 : 0.075).CGColor;
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOpacity = primary ? 0.17 : 0.10;
    button.layer.shadowRadius = primary ? 15 : 10;
    button.layer.shadowOffset = CGSizeMake(0, primary ? 8 : 5);
    return button;
}

- (UILabel *)label:(NSString *)text size:(CGFloat)size weight:(UIFontWeight)weight alpha:(CGFloat)alpha alignment:(NSTextAlignment)alignment {
    UILabel *label = [UILabel new];
    label.text = text;
    label.textColor = ADSColor(1, alpha);
    label.font = [UIFont systemFontOfSize:size weight:weight];
    label.textAlignment = alignment;
    label.numberOfLines = 1;
    return label;
}

- (void)resetInterface {
    [self setHeadline:@"Ready" animated:NO];
    self.logView.text = [NSString stringWithFormat:@"[00.000] boot: interface ready\n[00.004] dark: %@ modules staged\n[00.011] profile: %@ mode\n",
                         @(self.darkEngine.moduleNames.count),
                         self.darkEngine.modeLabel];
    [self setProgressValue:0 animated:NO];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.running && !self.finished && self.progressFillWidth.constant == 0) {
        self.progressFillWidth.constant = 0;
    }
}

- (void)setHeadline:(NSString *)text animated:(BOOL)animated {
    void (^changes)(void) = ^{
        self.headlineLabel.text = text;
        self.headlineLabel.transform = CGAffineTransformIdentity;
        self.headlineLabel.alpha = 0.94;
    };

    if (!animated) {
        changes();
        return;
    }

    [UIView animateWithDuration:0.16 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
        self.headlineLabel.alpha = 0.0;
        self.headlineLabel.transform = CGAffineTransformMakeTranslation(0, -5);
    } completion:^(BOOL finished) {
        self.headlineLabel.text = text;
        self.headlineLabel.transform = CGAffineTransformMakeTranslation(0, 5);
        [UIView animateWithDuration:0.26 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.headlineLabel.alpha = 0.94;
            self.headlineLabel.transform = CGAffineTransformIdentity;
        } completion:nil];
    }];
}

- (void)appendLog:(NSString *)line {
    NSString *current = self.logView.text ?: @"";
    self.logView.text = [current stringByAppendingFormat:@"%@\n", line];
    NSRange bottom = NSMakeRange(self.logView.text.length, 0);
    [self.logView scrollRangeToVisible:bottom];
}

- (void)setProgressValue:(CGFloat)value animated:(BOOL)animated {
    [self.view layoutIfNeeded];
    CGFloat width = self.progressTrack.bounds.size.width * value;
    self.progressFillWidth.constant = width;

    NSInteger percent = (NSInteger)lrint(value * 100.0);
    self.percentLabel.text = [NSString stringWithFormat:@"%ld%%", (long)percent];

    if (animated) {
        [UIView animateWithDuration:0.42 delay:0 usingSpringWithDamping:0.88 initialSpringVelocity:0.2 options:UIViewAnimationOptionCurveEaseOut animations:^{
            [self.view layoutIfNeeded];
        } completion:nil];

        self.percentLabel.transform = CGAffineTransformMakeScale(0.96, 0.96);
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.percentLabel.transform = CGAffineTransformIdentity;
        } completion:nil];
    }
}

- (void)buttonPressDown:(UIButton *)button {
    if (!button.enabled) return;
    [UIView animateWithDuration:0.18 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.25 options:UIViewAnimationOptionCurveEaseOut animations:^{
        button.transform = CGAffineTransformMakeScale(0.982, 0.982);
        button.alpha = 0.88;
    } completion:nil];
}

- (void)buttonPressUp:(UIButton *)button {
    [UIView animateWithDuration:0.26 delay:0 usingSpringWithDamping:0.82 initialSpringVelocity:0.35 options:UIViewAnimationOptionCurveEaseOut animations:^{
        button.transform = CGAffineTransformIdentity;
        button.alpha = button.enabled ? 1.0 : 0.86;
    } completion:nil];
}

- (void)setRunButtonDisabledLookWithTitle:(NSString *)title {
    [self.runButton setTitle:title forState:UIControlStateNormal];
    [self.runButton setTitle:title forState:UIControlStateDisabled];
    self.runButton.enabled = NO;
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        self.runButton.backgroundColor = ADSColor(0.082, 0.96);
        self.runButton.layer.borderColor = ADSColor(1, 0.052).CGColor;
        self.runButton.alpha = 0.86;
    } completion:nil];
}

- (NSString *)ads_cachedStandoff2InfoPlist {
    NSString *cached = [[NSUserDefaults standardUserDefaults] stringForKey:kADSCachedStandoff2PlistKey];
    if (cached.length && access(cached.fileSystemRepresentation, R_OK) == 0) {
        return cached;
    }
    return nil;
}

- (void)ads_cacheStandoff2InfoPlist:(NSString *)path {
    if (!path.length) return;
    [[NSUserDefaults standardUserDefaults] setObject:path forKey:kADSCachedStandoff2PlistKey];
}

- (NSString *)ads_standoff2InfoPlistFromWorkspace {
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) return nil;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
    id workspace = [wsClass performSelector:NSSelectorFromString(@"defaultWorkspace")];
    if (!workspace) return nil;

    SEL appsSel = NSSelectorFromString(@"allInstalledApplications");
    if (![workspace respondsToSelector:appsSel]) {
        appsSel = NSSelectorFromString(@"allApplications");
    }
    if (![workspace respondsToSelector:appsSel]) return nil;

    for (NSDictionary *app in [workspace performSelector:appsSel]) {
        if (![app isKindOfClass:[NSDictionary class]]) continue;
        NSString *bundleID = app[@"CFBundleIdentifier"] ?: app[@"BundleIdentifier"];
        if (![bundleID isEqualToString:kADSStandoff2BundleID]) continue;

        NSString *bundlePath = app[@"Path"] ?: app[@"BundlePath"] ?: app[@"CFBundlePath"];
        if (!bundlePath.length) continue;
        return [bundlePath stringByAppendingPathComponent:@"Info.plist"];
    }
#pragma clang diagnostic pop
    return nil;
}

- (NSString *)ads_standoff2InfoPlistInContainer:(const char *)basePath {
    DIR *root = opendir(basePath);
    if (!root) return nil;

    const char *appFolder = "Standoff2.app";
    struct dirent *entry = NULL;
    char plistPath[PATH_MAX];

    while ((entry = readdir(root)) != NULL) {
        if (entry->d_name[0] == '.') continue;

        int written = snprintf(plistPath, sizeof(plistPath), "%s/%s/%s/Info.plist",
                               basePath, entry->d_name, appFolder);
        if (written <= 0 || written >= (int)sizeof(plistPath)) continue;
        if (access(plistPath, R_OK) != 0) continue;

        NSString *plist = [NSString stringWithUTF8String:plistPath];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
        if ([info[@"CFBundleIdentifier"] isEqualToString:kADSStandoff2BundleID]) {
            closedir(root);
            return plist;
        }
    }

    closedir(root);
    return nil;
}

- (NSString *)ads_findStandoff2InfoPlist {
    NSString *cached = [self ads_cachedStandoff2InfoPlist];
    if (cached) return cached;

    NSString *found = [self ads_standoff2InfoPlistFromWorkspace];
    if (!found) {
        const char *bases[] = {
            "/private/var/containers/Bundle/Application",
            "/var/containers/Bundle/Application",
            NULL
        };
        for (int i = 0; bases[i] != NULL && !found; i++) {
            if (access(bases[i], R_OK) == 0) {
                found = [self ads_standoff2InfoPlistInContainer:bases[i]];
            }
        }
    }

    if (found) {
        [self ads_cacheStandoff2InfoPlist:found];
    }
    return found;
}

- (void)runSequence {
    if (self.running || self.finished) return;
    self.running = YES;
    [self setHeadline:@"Running" animated:YES];
    [self setRunButtonDisabledLookWithTitle:@"Running..."];
    [self setProgressValue:0 animated:NO];
    self.logView.text = @"";

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            self.logView.text = @"";
            [self appendLog:[NSString stringWithFormat:@"[*] Build %s %s", __DATE__, __TIME__]];
            [self appendLog:@"[00.000] [+] Initializing DarkSword exploit chain..."];
            [self setProgressValue:0.1 animated:YES];
        });

        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:@"[+] kexploit_opa334: launching..."];
        });
        int kret = kexploit_opa334();
        dispatch_async(dispatch_get_main_queue(), ^{
            [self appendLog:[NSString stringWithFormat:@"[+] kexploit_opa334 ret: %d", kret]];
            [self setProgressValue:0.4 animated:YES];
        });
        BOOL success = (kret == 0);

        if (success) {
            uint64_t self_proc = proc_find(getpid());
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"[*] self_proc: 0x%llx", self_proc]];
            });

            int sbx_ret = sandbox_escape(self_proc);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"[*] sandbox_escape ret: %d", sbx_ret]];
            });

            int root_ret = sandbox_elevate_to_root(self_proc);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self appendLog:[NSString stringWithFormat:@"[*] elevate_to_root ret: %d uid=%d", root_ret, getuid()]];
                [self setProgressValue:0.7 animated:YES];
            });

            usleep(200000);

            NSString *cachedPlist = [self ads_cachedStandoff2InfoPlist];
            self.foundGamePath = cachedPlist ?: [self ads_findStandoff2InfoPlist];
            NSString *foundPath = self.foundGamePath;
            BOOL fromCache = (cachedPlist != nil);
            dispatch_async(dispatch_get_main_queue(), ^{
                if (foundPath) {
                    [self appendLog:fromCache ? @"[*] Standoff2: cache hit" : @"[*] Standoff2: fast lookup"];
                    [self appendLog:[NSString stringWithFormat:@"[+] FOUND: %@", foundPath]];
                } else {
                    [self appendLog:@"[-] com.axlebolt.standoff2 not found"];
                }
            });
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self setProgressValue:1.0 animated:YES];
            if (success) {
                [self appendLog:@"[+] KERNEL R/W ACHIEVED"];
                [self appendLog:@"[+] SANDBOX ESCAPED"];
                [self appendLog:@"[+] ROOT ACHIEVED"];

                NSString *destPath = [self.foundGamePath stringByDeletingLastPathComponent];
                NSDictionary *bundleDestRel = @{
                    @"builtincollections_definitions": @"Data/Raw/DLC/BuiltInCollections/builtincollections_definitions.bundle",
                    @"hotwinterpartycollection_definitions": @"Data/Raw/BoltDLC/hotwinterpartycollection_definitions.bundle",
                };

                if (!destPath.length) {
                    [self appendLog:@"[-] foundGamePath пуст — некуда подменять"];
                } else {
                    for (NSString *bundleName in bundleDestRel) {
                        NSString *srcPath = [[NSBundle mainBundle] pathForResource:bundleName ofType:@"bundle"];
                        NSString *destRel = bundleDestRel[bundleName];
                        NSString *destPath2real = [destPath stringByAppendingPathComponent:destRel];
                        NSString *destPath2;
                        if ([destPath2real hasPrefix:@"/private/"]) {
                            destPath2 = destPath2real;
                        } else {
                            destPath2 = [destPath2real stringByReplacingOccurrencesOfString:@"/var/containers"
                                                                                 withString:@"/private/var/containers"];
                        }

                        if (!srcPath.length) {
                            [self appendLog:[NSString stringWithFormat:@"[-] [%@] нет в AntiDarkSword.app/Bundle", bundleName]];
                            continue;
                        }

                        struct stat stSrc = {0}, stDst = {0};
                        int srcOk = (stat([srcPath UTF8String], &stSrc) == 0);
                        int dstOk = (stat([destPath2 UTF8String], &stDst) == 0);
                        if (!dstOk) {
                            [self appendLog:[NSString stringWithFormat:@"[-] [%@] нет в игре: %@", bundleName, destPath2]];
                            continue;
                        }

                        uint64_t orig_vnode = 0, orig_v_data = 0;
                        bool ok = vnode_redirect_file(
                            [destPath2 UTF8String],
                            [srcPath UTF8String],
                            &orig_vnode,
                            &orig_v_data);
                        [self appendLog:[NSString stringWithFormat:@"[*] [%@] redirect=%d (%lld → %lld bytes)",
                            bundleName, (int)ok, (long long)stDst.st_size, (long long)stSrc.st_size]];
                        [self appendLog:ok ? [NSString stringWithFormat:@"[+] [%@] OK", bundleName]
                                        : [NSString stringWithFormat:@"[-] [%@] failed", bundleName]];
                    }
                }

                [self setHeadline:@"Complete" animated:YES];
            } else {
                [self appendLog:@"[-] Exploit failed"];
                [self setHeadline:@"Failed" animated:YES];
            }
            self.running = NO;
            self.finished = YES;
            [self setRunButtonDisabledLookWithTitle:success ? @"Done" : @"Failed"];
        });
    });
}

- (void)openTelegram {
    NSURL *url = [NSURL URLWithString:@"https://t.me/"];
    [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
}

- (void)animateIn:(UIView *)view {
    view.alpha = 0;
    view.transform = CGAffineTransformMakeTranslation(0, 10);
    [UIView animateWithDuration:0.44 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        view.alpha = 1;
        view.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)copyLogs {
    NSString *logs = self.logView.text;
    [UIPasteboard generalPasteboard].string = logs ? logs : @"";
    for (UIView *v in self.view.subviews) {
        if ([v isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)v;
            if ([[btn titleForState:UIControlStateNormal] isEqualToString:@"\U0001F4CB"]) {
                [btn setTitle:@"\u2705" forState:UIControlStateNormal];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [btn setTitle:@"\U0001F4CB" forState:UIControlStateNormal];
                });
                break;
            }
        }
    }
}

@end

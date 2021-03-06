//
//  PSPDFTextView.m
//  PSPDFKit
//
//  Copyright (c) 2013-2014 PSPDFKit GmbH. All rights reserved.
//

#import "PSPDFTextView.h"

#ifndef kCFCoreFoundationVersionNumber_iOS_7_0
#define kCFCoreFoundationVersionNumber_iOS_7_0 847.2
#endif

// Set this to YES if you only support iOS 7.
#define PSPDFRequiresTextViewWorkarounds() (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0)

@interface PSPDFTextView () <UITextViewDelegate>
@property (nonatomic, weak) id<UITextViewDelegate> realDelegate;
@end

@implementation PSPDFTextView

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSObject

- (id)initWithFrame:(CGRect)frame textContainer:(NSTextContainer *)textContainer {
    if (self = [super initWithFrame:frame textContainer:textContainer]) {
        if (PSPDFRequiresTextViewWorkarounds()) {
            [super setDelegate:self];
        }
    }
    return self;
}

- (void)dealloc {
    self.delegate = nil;
}

- (void)setDelegate:(id<UITextViewDelegate>)delegate {
    if (PSPDFRequiresTextViewWorkarounds()) {
        // UIScrollView delegate keeps some flags that mark whether the delegate implements some methods (like scrollViewDidScroll:)
        // setting *the same* delegate doesn't recheck the flags, so it's better to simply nil the previous delegate out
        // we have to setup the realDelegate at first, since the flag check happens in setter
        [super setDelegate:nil];
        self.realDelegate = delegate != self ? delegate : nil;
        [super setDelegate:delegate ? self : nil];
    }else {
        [super setDelegate:delegate];
    }
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Caret Scrolling

- (UIScrollView *)hostScrollView {
	UIView *view = self;
	while (view) {
		if ([view isKindOfClass:[UIScrollView class]]) {
			UIScrollView *scrollView = (UIScrollView *)view;
            BOOL scrollable = (scrollView.scrollEnabled && scrollView.contentSize.height + scrollView.contentInset.top + scrollView.contentInset.bottom > scrollView.bounds.size.height);
			if (scrollable) {
				return scrollView;
			}
		}
		view = view.superview;
	}
	return nil;
}

- (CGRect)rectForScrollingToVisibleWithProposedRect:(CGRect)proposedRect {
    return proposedRect;
}

- (void)scrollRectToVisibleConsideringInsets:(CGRect)rect animated:(BOOL)animated {
    if (PSPDFRequiresTextViewWorkarounds()) {
		UIScrollView *hostScrollView = [self hostScrollView];
		
		CGRect visibleRect = UIEdgeInsetsInsetRect(hostScrollView.bounds, hostScrollView.contentInset);
        
        rect = [self rectForScrollingToVisibleWithProposedRect:rect];
		rect = [hostScrollView convertRect:rect fromView:self];
        
        // Don't scroll if rect is currently visible.
        if (!CGRectContainsRect(visibleRect, rect)) {
            // Calculate new content offset.
            CGPoint contentOffset = hostScrollView.contentOffset;
            if (CGRectGetMinY(rect) < CGRectGetMinY(visibleRect)) { // scroll up
                contentOffset.y = CGRectGetMinY(rect) - hostScrollView.contentInset.top;
            }else { // scroll down
                contentOffset.y = CGRectGetMaxY(rect) + hostScrollView.contentInset.bottom - CGRectGetHeight(hostScrollView.bounds);
            }
            [hostScrollView setContentOffset:contentOffset animated:animated];
        }
    }
    else {
        [self scrollRectToVisible:rect animated:animated];
    }
}

- (void)scrollRangeToVisibleConsideringInsets:(NSRange)range animated:(BOOL)animated {
    if (PSPDFRequiresTextViewWorkarounds()) {
        // Calculate text position and scroll, considering insets.
        UITextPosition *startPosition = [self positionFromPosition:self.beginningOfDocument offset:range.location];
        UITextPosition *endPosition = [self positionFromPosition:startPosition offset:range.length];
        UITextRange *textRange = [self textRangeFromPosition:startPosition toPosition:endPosition];
        [self scrollRectToVisibleConsideringInsets:[self firstRectForRange:textRange] animated:animated];
    }
    else {
        [self scrollRangeToVisible:range];
    }
}

- (void)ensureCaretIsVisibleWithReplacementText:(NSString *)text {
    // No action is required on iOS 6, everything's working as intended there.
    if (PSPDFRequiresTextViewWorkarounds()) {
        // We need to give UITextView some time to fix it's calculation if this is a newline and we're at the end.
        if ([text isEqualToString:@"\n"] || [text isEqualToString:@""]) {
            // We schedule scrolling and don't animate, since UITextView doesn't animate these changes as well.
            [self scheduleScrollToVisibleCaretWithDelay:0.1f]; // Smaller delays are unreliable.
        }else {
            // Whenever the user enters text, see if we need to scroll to keep the caret on screen.
            // If it's not a newline, we don't need to add a delay to scroll.
            // We don't animate since this sometimes ends up on the wrong position then.
            [self scrollToVisibleCaret];
        }
    }
}

- (void)scheduleScrollToVisibleCaretWithDelay:(NSTimeInterval)delay {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scrollToVisibleCaret) object:nil];
    [self performSelector:@selector(scrollToVisibleCaret) withObject:nil afterDelay:delay];
}

- (void)scrollToVisibleCaretAnimated:(BOOL)animated {
    [self scrollRectToVisibleConsideringInsets:[self caretRectForPosition:self.selectedTextRange.end] animated:animated];
}

- (void)scrollToVisibleCaret {
    [self scrollToVisibleCaretAnimated:YES];
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UIResponder

- (BOOL)becomeFirstResponder {
    BOOL didBecome = [super becomeFirstResponder];
    if (didBecome) {
        [self scheduleScrollToVisibleCaretWithDelay:0.1];
    }
    return didBecome;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - UITextViewDelegate

- (void)textViewDidChangeSelection:(UITextView *)textView {
    id<UITextViewDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate textViewDidChangeSelection:textView];
    }

    // Ensure caret stays visible when we change the caret position (e.g. via keyboard)
    if ([self isFirstResponder]) {
        [self scheduleScrollToVisibleCaretWithDelay:0.1];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    id<UITextViewDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        [delegate textViewDidChange:textView];
    }

    // Ensure we scroll to the caret position when changing text (e.g. pasting)
    [self scheduleScrollToVisibleCaretWithDelay:0.1];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    BOOL returnVal = YES;
    id<UITextViewDelegate> delegate = self.realDelegate;
    if ([delegate respondsToSelector:_cmd]) {
        returnVal = [delegate textView:textView shouldChangeTextInRange:range replacementText:text];
    }

    // Ensure caret stays visible while we type.
    [self ensureCaretIsVisibleWithReplacementText:text];
    return returnVal;
}

///////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Delegate Forwarder

- (BOOL)respondsToSelector:(SEL)s {
    return [super respondsToSelector:s] || [self.realDelegate respondsToSelector:s];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)s {
    return [super methodSignatureForSelector:s] ?: [(id)self.realDelegate methodSignatureForSelector:s];
}

- (id)forwardingTargetForSelector:(SEL)s {
    id delegate = self.realDelegate;
    return [delegate respondsToSelector:s] ? delegate : [super forwardingTargetForSelector:s];
}

@end

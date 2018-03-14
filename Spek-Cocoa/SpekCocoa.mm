//
//  SpekCocoa.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 02/22/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import <Foundation/Foundation.h>

#import <pthread.h>

#import "SpekCocoa.h"

#import "Audio.hpp"
#import "FFT.hpp"
#import "Palette.hpp"
#import "RulerView.h"
#import "SpectrogramView.h"
#import "PalleteView.h"

#define NFFT 64 // Number of FFTs to pre-fetch.
#define IMAGE_SAMPLE_BITS 8

#define DEBUG_MULTITHREAD
#undef DEBUG_MULTITHREAD

#pragma mark - SpekWindow
@implementation SpekWindow

-(NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self.dragNDropDelegate draggingEntered:sender];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    return [self.dragNDropDelegate performDragOperation:sender];
}

@end

#pragma mark - WINDOW_FUNCTION
enum WINDOW_FUNCTION {
    WINDOW_HANN = 0,
    WINDOW_HAMMING,
    WINDOW_BLACKMAN_HARRIS,
    WINDOW_COUNT,
    WINDOW_DEFAULT = WINDOW_HANN,
};

#pragma mark - Processor
struct Processor {
    AudioFile* audioFile;
    FFTPlan* fftPlan;
    enum WINDOW_FUNCTION window;
    float *coss;      // Pre-computed cos table.
    NSInteger nfft;   // Size of the FFT transform.
    
    NSUInteger stream;
    NSUInteger channel;
    NSInteger samples;
    
    float *input;
    float *output;
    
    NSInteger input_size;
    NSInteger input_pos;
    
    BOOL worker_done;
    
    BOOL quit;
};

#pragma mark - SpekCocoa
@interface SpekCocoa ()
{
    Audio* audio;
    FFT* fft;
    Processor* processor;
    
    void *isOnReaderQueueSpecific;
}

@property IBOutlet RulerView *frequencyRulerView;
@property IBOutlet RulerView *intensityRulerView;
@property IBOutlet RulerView *timeRulerView;

@property IBOutlet PalleteView *paletteView;
@property IBOutlet SpectrogramView *spectrogramView;

@property IBOutlet NSTextField *fileLabel;
@property IBOutlet NSTextField *streamPropLabel;

@property (copy) NSString *filePath;

@property (strong) NSBitmapImageRep* spectrogramBitmap;
@property (strong) NSBitmapImageRep* paletteBitmap;

@property NSSize sizePre;

@property dispatch_queue_t readerDispatchQueue;
@property dispatch_queue_t workerDispatchQueue;

@property NSOperationQueue *readerQueue;
@property NSOperationQueue *workerQueue;

@property pthread_cond_t readerCond;
@property pthread_cond_t workerCond;

@property pthread_mutex_t readerMutex;
@property pthread_mutex_t workerMutex;

@end

@implementation SpekCocoa

- (instancetype)init {
    if (self = [super init]) {
        
        self->audio = new Audio;
        self->fft = new FFT;
        
        self.readerQueue = [NSOperationQueue new];
        self.workerQueue = [NSOperationQueue new];
        
        self.readerDispatchQueue = dispatch_queue_create("reader", DISPATCH_QUEUE_SERIAL);
        self.workerDispatchQueue = dispatch_queue_create("worker", DISPATCH_QUEUE_SERIAL);
        
        dispatch_queue_set_specific(_readerDispatchQueue, &isOnReaderQueueSpecific, (__bridge void *)self, nil);
        
        self.readerQueue.underlyingQueue = _readerDispatchQueue;
        self.workerQueue.underlyingQueue = _workerDispatchQueue;
        
        pthread_mutex_init(&self->_readerMutex, NULL);
        pthread_mutex_init(&self->_workerMutex, NULL);
        
        pthread_cond_init(&self->_readerCond, NULL);
        pthread_cond_init(&self->_workerCond, NULL);
    }
    return self;
}

- (void)dealloc {
#ifdef DEBUG
    NSLog(@"dealloc");
#endif
    
    pthread_mutex_destroy(&self->_readerMutex);
    pthread_mutex_destroy(&self->_workerMutex);
    pthread_cond_destroy(&self->_readerCond);
    pthread_cond_destroy(&self->_workerCond);
    
    delete self->audio;     self->audio = NULL;
    delete self->fft;       self->fft = NULL;
    delete self->processor; self->processor = NULL;
}

#pragma mark -
#pragma mark Events

- (void)windowDidResize:(NSNotification *)notification {
    NSWindow* window = notification.object;
    NSSize size = window.contentView.bounds.size;
    
    if (size.width != self.sizePre.width) {
        [self startWithPath: self.filePath];
    }
    
    self.sizePre = size;
}

- (void)awakeFromNib {
    self.window.dragNDropDelegate = self;
    [self.window registerForDraggedTypes:@[NSURLPboardType]];
    self.window.movableByWindowBackground = true;
    
    self.fileLabel.stringValue = [NSString stringWithFormat:@"File: -"];
    self.streamPropLabel.stringValue = [NSString stringWithFormat:@"Details: -"];
    
    self.frequencyRulerView.position = Left;
    self.frequencyRulerView.factors = @[@1e3, @2e3, @5e3, @1e4, @2e4, @0];
    self.frequencyRulerView.minimum = 0;
    self.frequencyRulerView.maximum = 0;
    self.frequencyRulerView.unitSpacing = 3.;
    self.frequencyRulerView.labelExample = @"00 kHz";
    self.frequencyRulerView.formatter = ^(NSInteger unit) {
        return [NSString stringWithFormat:@"%ld kHz", unit / 1000];
    };
    
    self.timeRulerView.position = Bottom;
    self.timeRulerView.factors = @[@1, @2, @5, @10, @20, @30, @(1*60), @(2*60), @(5*60), @(10*60), @(20*60), @(30*60), @0];
    self.timeRulerView.minimum = 0;
    self.timeRulerView.maximum = 0;
    self.timeRulerView.unitSpacing = 1.5;
    self.timeRulerView.labelExample = @"00:00";
    self.timeRulerView.formatter = ^(NSInteger unit) {
        return [NSString stringWithFormat:@"%ld:%02ld", unit / 60, unit % 60];
    };
    
    self.intensityRulerView.position = Right;
    self.intensityRulerView.factors = @[@1, @2, @5, @10, @20, @50, @0];
    self.intensityRulerView.minimum = -120;
    self.intensityRulerView.maximum = 0;
    self.intensityRulerView.unitSpacing = 3.;
    self.intensityRulerView.labelExample = @"-00 dB";
    self.intensityRulerView.formatter = ^(NSInteger unit) {
        return [NSString stringWithFormat:@"%ld dB", unit];
    };
    
    self.window.titleVisibility = NSWindowTitleHidden;
    self.window.titlebarAppearsTransparent = YES;
    self.window.styleMask |= NSWindowStyleMaskFullSizeContentView;
    
    self.window.backgroundColor = [NSColor colorWithDeviceRed:0 green:0 blue:0 alpha:0.9];
    self.window.opaque = NO;
}

#pragma mark -
#pragma mark Drawing

- (void)finish {
    [self stopProcess];
    [self.spectrogramView finish];
}

#pragma mark -
#pragma mark Public Interface
- (void)startWithPath:(NSString *)path {
    if (![path length]) {
        return;
    }
    self.filePath = path;
    [self stopProcess];
    [self prepareProcessorWithAudioFile: self->audio->open([path UTF8String], 0)
                                FFTPlan: self->fft->create(11)
                                 Stream: 0
                                Channel: 0
                         WindowFunction: WINDOW_DEFAULT
                                Samples: self.spectrogramView.bounds.size.width];
    
    self.fileLabel.stringValue = [NSString stringWithFormat:@"File: %@", self.filePath];
    self.streamPropLabel.stringValue = [NSString stringWithFormat:@"Details: %@", [self information]];
    
    self.timeRulerView.maximum = (NSInteger)self->processor->audioFile->get_duration();
    self.frequencyRulerView.maximum = self->processor->audioFile->get_sample_rate() / 2;
    [self.timeRulerView setNeedsDisplay:YES];
    [self.frequencyRulerView setNeedsDisplay:YES];
    
    [self startProcess];
}

#pragma mark -
#pragma mark Processing Control

- (void)prepareProcessorWithAudioFile:(AudioFile*)file FFTPlan:(FFTPlan*)fftPlan Stream:(NSInteger)stream Channel:(NSInteger)channel WindowFunction:(enum WINDOW_FUNCTION)window Samples:(NSInteger)samples {
    self->processor = new Processor;
    assert(self->processor);
    self->processor->audioFile = file;
    self->processor->fftPlan   = fftPlan;
    self->processor->stream    = stream;
    self->processor->channel   = channel;
    self->processor->window    = window;
    self->processor->samples   = samples;
    
    self->processor->coss = NULL;
    
    self->processor->input  = NULL;
    self->processor->output = NULL;
    
    if (!self->processor->audioFile->get_error()) {
        self->processor->nfft = self->processor->fftPlan->get_input_size();
        self->processor->coss = (float*)malloc(self->processor->nfft * sizeof(float));
        float cf = 2.0f * (float)M_PI / (self->processor->nfft - 1.0f);
        for (int i = 0; i < self->processor->nfft; i++) {
            self->processor->coss[i] = cosf(cf * i);
        }
        self->processor->input_size = self->processor->nfft * (NFFT * 2 + 1);
        self->processor->input  = (float*)malloc(self->processor->input_size * sizeof(float));
        self->processor->output = (float*)malloc(self->processor->fftPlan->get_output_size() * sizeof(float));
        self->processor->audioFile->start((int)channel, (int)samples);
    }
}

- (void)startProcess {
    [self.spectrogramView reset];
    
    if (self->processor->audioFile->get_error() != AudioError::OK) {
        return;
    }
    
    self->processor->input_pos = 0;
    self->processor->worker_done = NO;
    
    self->processor->quit = NO;
    
    [self.readerQueue addOperationWithBlock:^{
        [self read];
    }];
    
    [self.workerQueue addOperationWithBlock:^{
        [self work];
    }];
    
    dispatch_barrier_async(self.readerQueue.underlyingQueue, ^{
        [[NSOperationQueue mainQueue] addOperationWithBlock: ^{
            [self.spectrogramView setNeedsDisplay:YES];
        }];
    });
}

- (void)read {
    NSInteger pos = 0, prev_pos = 0;
    NSInteger len;
    while ((len = processor->audioFile->read()) > 0) {
        if (processor->quit) {
            break;
        }
        
        const float *buffer = processor->audioFile->get_buffer();
        while (len-- > 0) {
            processor->input[pos] = *buffer++;
            pos = (pos + 1) % processor->input_size;
            
            // Wake up the worker if we have enough data.
            if ((pos > prev_pos ? pos : pos + processor->input_size) - prev_pos == processor->nfft * NFFT) {
//                NSLog(@"-----r----- have enough data, pos: %ld, pre_pos: %ld", pos, prev_pos);
#ifdef DEBUG_MULTITHREAD
                NSLog(@"[%@] - reader done", [NSDate date]);
#endif
                [self syncWorkerWithPos:prev_pos = pos];
            }
        }
        assert(len == -1);
    }
    
    if (pos != prev_pos) {
        [self syncWorkerWithPos:pos];
    }
    
    [self syncWorkerWithPos:-1]; // Force the worker to quit.
    dispatch_sync(self.workerQueue.underlyingQueue, ^{});
    
    [self finish];
}

- (void)work {
    NSInteger sample = 0;
    NSInteger frames = 0;
    NSInteger num_fft = 0;
    NSInteger acc_error = 0;
    NSInteger head = 0, tail = 0;
    NSInteger prev_head = 0;
    
    memset(processor->output, 0, sizeof(float) * processor->fftPlan->get_output_size());
    
    while (true) {
        pthread_mutex_lock(&self->_readerMutex);
#ifdef DEBUG_MULTITHREAD
        NSLog(@"[%@] - \t\t\t\t\t\t\t\t\tsignal semReader", [NSDate date]);
#endif
        processor->worker_done = YES;
        pthread_cond_signal(&self->_readerCond);
        pthread_mutex_unlock(&self->_readerMutex);
        
        pthread_mutex_lock(&self->_workerMutex);
#ifdef DEBUG_MULTITHREAD
        NSLog(@"[%@] - \t\t\t\t\t\t\t\t\tread done? %@", [NSDate date], tail == processor->input_pos ? @"YES" : @"NO");
#endif
        while (tail == processor->input_pos) {
            pthread_cond_wait(&self->_workerCond, &self->_workerMutex);
        }
        tail = processor->input_pos;
        pthread_mutex_unlock(&self->_workerMutex);
        
        if (tail == -1) {
            return;
        }
        
//        NSLog(@"\t\t\t\t-----w----- tail: %ld", tail);
        
        while (true) {
            head = (head + 1) % processor->input_size;
            if (head == tail) {
//                NSLog(@"head == tail: %ld", tail);
                head = prev_head;
                break;
            }
            frames++;
            
//            NSLog(@"head: %ld, frames: %ld", head, frames);
            
            // If we have enough frames for an FFT or we have
            // all frames required for the interval run and FFT.
            bool int_full = acc_error <  processor->audioFile->get_error_base() &&
            frames == processor->audioFile->get_frames_per_interval();
            
            bool int_over = acc_error >= processor->audioFile->get_error_base() &&
            frames == 1 + processor->audioFile->get_frames_per_interval();
            
            if (frames % processor->nfft == 0 || ((int_full || int_over) && num_fft == 0)) {
//                NSLog(@"\t\t\t\t-----w----- process from: %ld, frame: %ld", ((processor->input_size + head - processor->nfft) % processor->input_size), frames);
//                NSLog(@"\t\t\t\t-----w----- head: %ld, pre_head: %ld", head, prev_head);
                prev_head = head;
                for (int i = 0; i < processor->nfft; i++) {
                    float val = processor->input[(processor->input_size + head - processor->nfft + i) % processor->input_size];
                    val *= getWindow(processor->window, i, processor->coss, processor->nfft);
                    processor->fftPlan->set_input(i, val);
                }
                processor->fftPlan->execute();
                num_fft++;
                for (int i = 0; i < processor->fftPlan->get_output_size(); i++) {
                    processor->output[i] += processor->fftPlan->get_output(i);
                }
            }
            
            // Do we have the FFTs for one interval?
            if (int_full || int_over) {
                if (int_over)
                    acc_error -= processor->audioFile->get_error_base();
                else
                    acc_error += processor->audioFile->get_error_per_interval();
                
                for (int i = 0; i < processor->fftPlan->get_output_size(); i++) {
                    processor->output[i] /= num_fft;
                }
                
                if (sample == processor->samples) break;
                
//                    NSLog(@"[%@] - \t\t\t\t\t\t\t\tworker done", [NSDate date]);
                
//                float *dataCopy = (float*)malloc(self->processor->fftPlan->get_output_size() * sizeof(float));
//                memcpy(dataCopy, processor->output, self->processor->fftPlan->get_output_size() * sizeof(float));
                
                [self.spectrogramView setDataAtSample: sample
                                                bands: processor->fftPlan->get_output_size()
                                             withData: processor->output];
                
                ++sample;
                
                memset(processor->output, 0, sizeof(float) * processor->fftPlan->get_output_size());
                
                frames = 0;
                num_fft = 0;
            }
        }
//        NSLog(@"\t\t\t\tprocessing data end");
    }
}

- (void)syncWorkerWithPos:(NSInteger) pos {
    pthread_mutex_lock(&self->_readerMutex);
#ifdef DEBUG_MULTITHREAD
    NSLog(@"[%@] - \twork done? %@", [NSDate date], processor->worker_done ? @"YES" : @"NO");
#endif
    while (!processor->worker_done) {
        pthread_cond_wait(&self->_readerCond, &self->_readerMutex);
    }
    processor->worker_done = NO;
    pthread_mutex_unlock(&self->_readerMutex);
    
    pthread_mutex_lock(&self->_workerMutex);
#ifdef DEBUG_MULTITHREAD
    NSLog(@"[%@] - \tsignal semWorker", [NSDate date]);
#endif
    processor->input_pos = pos;
    pthread_cond_signal(&self->_workerCond);
    pthread_mutex_unlock(&self->_workerMutex);
}

- (void)stopProcess {
    if (self->processor) {
        [self clean];
        delete processor;
        processor = NULL;
        
        dispatch_sync(self.workerQueue.underlyingQueue, ^{
#ifdef DEBUG
            NSLog(@"%ld operations in main queue will be cancelled", [[NSOperationQueue mainQueue] operations].count);
#endif
            [[[NSOperationQueue mainQueue] operations] makeObjectsPerformSelector:@selector(cancel)];
        });
    }
}

- (void)clean {
    processor->quit = YES;
    
    void (^cleanBlock)() = ^{
        if (processor->output) { free(processor->output); processor->output = NULL; }
        if (processor->input)  { free(processor->input);  processor->input  = NULL; }
        if (processor->coss)   { free(processor->coss);   processor->coss   = NULL; }
        
        delete processor->audioFile;
        processor->audioFile = NULL;
    };
    
    if (dispatch_get_specific(&self->isOnReaderQueueSpecific)) {
        cleanBlock();
    } else {
        dispatch_sync(self.readerQueue.underlyingQueue, ^{});
    }
}

float getWindow(enum WINDOW_FUNCTION window, NSInteger index, float *coss, NSInteger nfft) {
    switch (window) {
        case WINDOW_HANN:
        {
            return 0.5f * (1.0f - coss[index]);
            break;
        }
        case WINDOW_HAMMING:
        {
            return 0.53836f - 0.46164f * coss[index];
            break;
        }
        case WINDOW_BLACKMAN_HARRIS:
        {
            return 0.35875f - 0.48829f * coss[index]
                            + 0.14128f * coss[2 * index % nfft]
                            - 0.01168f * coss[3 * index % nfft];
            break;
        }
        default:
        {
            assert(false); return 0.0f; break;
        }
    }
    return 0.0f;
}

#pragma mark -
#pragma mark Tool Functions

- (NSString *)information {
    NSMutableArray<NSString *> *contents = [NSMutableArray arrayWithCapacity:7];
    
    if (!processor->audioFile->get_codec_name().empty()) {
        [contents addObject:[NSString stringWithUTF8String:processor->audioFile->get_codec_name().c_str()]];
    }
    
    if (int bitRate = processor->audioFile->get_bit_rate()) {
        [contents addObject:[NSString stringWithFormat:@"%d kbps", (processor->audioFile->get_bit_rate() + 500) / 1000]];
    }
    
    if (processor->audioFile->get_sample_rate()) {
        [contents addObject:[NSString stringWithFormat:@"%d Hz", processor->audioFile->get_sample_rate()]];
    }
    
    // Include bits per sample only if there is no bitrate.
    if (int bits = processor->audioFile->get_bits_per_sample() && !processor->audioFile->get_bit_rate()) {
        
        [contents addObject:[NSString stringWithFormat:@"%d %@", bits, bits > 1 ? @"bits" : @"bit"]];
    }
    
    if (processor->audioFile->get_channels()) {
        [contents addObject:[NSString stringWithFormat:@"channel %lu / %d", processor->channel + 1, processor->audioFile->get_channels()]];
    }
    
    if (processor->audioFile->get_error() == AudioError::OK) {
        [contents addObject:[NSString stringWithFormat:@"W:%ld", processor->nfft]];
        
        [contents addObject:[NSString stringWithFormat:@"F: %@", ^NSString *(void){
            switch (processor->window) {
                case WINDOW_HANN:            return @"Hann";            break;
                case WINDOW_HAMMING:         return @"Hamming";         break;
                case WINDOW_BLACKMAN_HARRIS: return @"Blackman–Harris"; break;
                default: assert(false);
            }
        }()]];
    }
    
    NSString *info = [contents componentsJoinedByString:@", "];
    
    NSString *error = ^NSString *() {;
        switch (processor->audioFile->get_error()) {
            case AudioError::CANNOT_OPEN_FILE:
                return @"Cannot open input file";
            case AudioError::NO_STREAMS:
                return @"Cannot find stream info";
            case AudioError::NO_AUDIO:
                return @"The file contains no audio streams";
            case AudioError::NO_DECODER:
                return @"Cannot find decoder";
            case AudioError::NO_DURATION:
                return @"Unknown duration";
            case AudioError::NO_CHANNELS:
                return @"No audio channels";
            case AudioError::CANNOT_OPEN_DECODER:
                return @"Cannot open decoder";
            case AudioError::BAD_SAMPLE_FORMAT:
                return @"Unsupported sample format";
            case AudioError::OK:
                return [NSString string];
        }
    }();
    
    if ([info length] == 0) {
        info = error;
    } else if (processor->stream < processor->audioFile->get_streams()) {
        info = [NSString stringWithFormat:@"Stream %lu / %d: %@", processor->stream + 1, processor->audioFile->get_streams(), info];
    } else if ([error length] > 0) {
        info = [NSString stringWithFormat:@"%@, %@", error, info];
    }
    
    return info;
}

-(NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    
    if ([[[sender draggingPasteboard] types] containsObject:NSURLPboardType]) {
        if ([sender draggingSourceOperationMask] & NSDragOperationLink) {
            return NSDragOperationCopy;
        } else if ([sender draggingSourceOperationMask] & NSDragOperationCopy) {
            return  NSDragOperationCopy;
        }
    }
    
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    if ([[[sender draggingPasteboard] types] containsObject:NSURLPboardType]) {
        NSURL *fileURL = [NSURL URLFromPasteboard:[sender draggingPasteboard]];
        [self startWithPath:[fileURL path]];
    }
    return true;
}

@end

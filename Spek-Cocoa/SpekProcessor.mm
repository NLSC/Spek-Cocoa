//
//  SpekProcessor.m
//  Spek-Cocoa
//
//  Created by SwanCurve on 02/25/17.
//  Copyright © 2017 SwanCurve. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "SpekProcessor.hpp"

#include "Audio.hpp"
#include "FFT.hpp"

#import <pthread.h>

#define NFFT 64 // Number of FFTs to pre-fetch.

@interface SpekProcesser ()
{
    pthread_t reader_thread;
    pthread_mutex_t reader_mutex;
    pthread_cond_t reader_cond;
    
    pthread_t worker_thread;
    pthread_mutex_t worker_mutex;
    pthread_cond_t worker_cond;
    
}

@property AudioFile* file;
@property FFTPlan* fft;
@property enum WINDOW_FUNCTION window;
@property float *coss;      // Pre-computed cos table.
@property NSInteger nfft;   // Size of the FFT transform.

@property NSUInteger stream;
@property NSUInteger channel;
@property NSInteger samples;

@property float *input;
@property float *output;

@property NSInteger input_size;
@property NSInteger input_pos;

@property BOOL has_reader_thread;
@property BOOL has_reader_mutex;
@property BOOL has_reader_cond;

@property BOOL has_worker_thread;
@property BOOL has_worker_mutex;
@property BOOL has_worker_cond;

@property BOOL worker_done;
@property volatile BOOL quit;

@end

@implementation SpekProcesser

@synthesize file = _file;
@synthesize fft = _fft;
@synthesize window = _window;
@synthesize coss = _coss;
@synthesize nfft = _nfft;

@synthesize stream = _stream;
@synthesize channel = _channel;
@synthesize samples = _samples;

@synthesize input = _input;
@synthesize output = _output;

@synthesize input_size = _input_size;
@synthesize input_pos = _input_pos;

@synthesize has_reader_thread = _has_reader_thread;
@synthesize has_reader_mutex = _has_reader_mutex;
@synthesize has_reader_cond = _has_reader_cond;

@synthesize has_worker_thread = _has_worker_thread;
@synthesize has_worker_mutex = _has_worker_mutex;
@synthesize has_worker_cond= _has_worker_cond;

@synthesize worker_done = _worker_done;
@synthesize quit = _quit;

#pragma mark -
#pragma mark Initialization
- (instancetype)initProcesserWithAudioFile:(AudioFileStruct*)file
                                   FFTPlan:(FFTPlanStruct*)fft
                                    Stream:(NSUInteger)stream
                                   Channel:(NSUInteger)channel
                            WindowFunction:(WINDOW_FUNCTION)window
                                   Samples:(NSUInteger)samples {

    if (self = [super init]) {
        self.file = file->ptr.get();
        self.fft = fft->ptr.get();
        self.stream = stream;
        self.channel = channel;
        self.window = window;
        self.samples = samples;
        
        self.coss = NULL;
        
        self.input  = NULL;
        self.output = NULL;
        
        self.has_reader_thread = NO;
        self.has_reader_mutex  = NO;
        self.has_reader_cond   = NO;
        
        self.has_worker_thread = NO;
        self.has_worker_mutex  = NO;
        self.has_worker_cond   = NO;
        
        if (!self.file->get_error()) {
            self.nfft = self.fft->get_input_size();
            self.coss = (float*)malloc(self.nfft * sizeof(float));
            float cf = 2.0f * (float)M_PI / (self.nfft - 1.0f);
            for (int i = 0; i < self.nfft; i++) {
                self.coss[i] = cosf(cf * i);
            }
            self.input_size = self.nfft * (NFFT * 2 + 1);
            self.input = (float*)malloc(self.input_size * sizeof(float));
            self.output = (float*)malloc(self.fft->get_output_size() * sizeof(float));
            self.file->start((int)channel, (int)samples);
        }
    }
    
    return self;
}

#pragma mark -
#pragma mark Processing Function
/*
void* reader_func(void* p);
void* worker_func(void* p);
void sync(SpekProcesser* p, NSInteger pos);

- (void)start {
    if (self.file->get_error() != AudioError::OK) {
        return;
    }
    
    self.input_pos = 0;
    self.worker_done = NO;
    self.quit = NO;
    
    self.has_reader_mutex = !pthread_mutex_init(&self->reader_mutex, NULL);
    self.has_reader_cond  = !pthread_cond_init(&self->reader_cond,   NULL);
    self.has_worker_mutex = !pthread_mutex_init(&self->worker_mutex, NULL);
    self.has_worker_cond  = !pthread_cond_init(&self->worker_cond,   NULL);
    
    self.has_reader_thread = !pthread_create(&self->reader_thread, NULL, &reader_func, self);
    if (!self.has_reader_thread) {
        [self close];
    }
}

- (void)close {
    if (self.has_reader_thread) {
        self.quit = YES;
        pthread_join(self->reader_thread, NULL);
        self.has_reader_thread = NO;
    }
    
    if (self.has_worker_cond)   { pthread_cond_destroy(&self->worker_cond);   self.has_worker_cond  = NO; }
    if (self.has_worker_mutex)  { pthread_mutex_destroy(&self->worker_mutex); self.has_worker_mutex = NO; }
    if (self.has_reader_cond)   { pthread_cond_destroy(&self->reader_cond);   self.has_reader_cond  = NO; }
    if (self.has_reader_mutex)  { pthread_mutex_destroy(&self->reader_mutex); self.has_reader_mutex = NO; }
    
    if (self.output) { free(self.output);  self.output = NULL;  }
    if (self.input)  { free(self.input);   self.input  = NULL;  }
    if (self.coss)   { free(self.coss);    self.coss   = NULL;  }
    
    delete self.file;
    self.file = NULL;
}

void* reader_func(void* p)
{
    SpekProcesser* processor = (SpekProcesser*)p;
    
    processor.has_worker_thread = !pthread_create(&processor->worker_thread, NULL, &worker_func, p);
    if (!processor.has_worker_thread) {
        return NULL;
    }
    
    NSInteger pos = 0, prev_pos = 0;
    NSInteger len;
    while ((len = processor.file->read()) > 0) {
        if (processor.quit) break;
        
        const float *buffer = processor.file->get_buffer();
        while (len-- > 0) {
            processor.input[pos] = *buffer++;
            pos = (pos + 1) % processor.input_size;
            
            // Wake up the worker if we have enough data.
            if ((pos > prev_pos ? pos : pos + processor.input_size) - prev_pos == processor.nfft * NFFT) {
                sync(processor, prev_pos = pos);
            }
        }
        assert(len == -1);
    }
    
    if (pos != prev_pos) {
        // Process the remaining data.
        sync(processor, pos);
    }
    
    // Force the worker to quit.
    sync(processor, -1);
    pthread_join(processor->worker_thread, NULL);
    
    // Notify the client.
    [processor performSelectorOnMainThread:@selector(update) withObject:nil waitUntilDone:NO];
    //    p->cb(p->fft->get_output_size(), -1, NULL, p->cb_data);
    return NULL;
}

void sync(SpekProcesser* processor, NSInteger pos)
{
    pthread_mutex_lock(&processor->reader_mutex);
    while (!processor.worker_done) {
        pthread_cond_wait(&processor->reader_cond, &processor->reader_mutex);
    }
    processor.worker_done = NO;
    pthread_mutex_unlock(&processor->reader_mutex);
    
    pthread_mutex_lock(&processor->worker_mutex);
    processor.input_pos = pos;
    pthread_cond_signal(&processor->worker_cond);
    pthread_mutex_unlock(&processor->worker_mutex);
}

void* worker_func(void* p)
{
    SpekProcesser* processor = (SpekProcesser*)p;
    
    NSInteger sample = 0;
    NSInteger frames = 0;
    NSInteger num_fft = 0;
    NSInteger acc_error = 0;
    NSInteger head = 0, tail = 0;
    NSInteger prev_head = 0;
    
    memset(processor.output, 0, sizeof(float) * processor.fft->get_output_size());
    
    while (true) {
        pthread_mutex_lock(&processor->reader_mutex);
        processor.worker_done = YES;
        pthread_cond_signal(&processor->reader_cond);
        pthread_mutex_unlock(&processor->reader_mutex);
        
        pthread_mutex_lock(&processor->worker_mutex);
        while (tail == processor.input_pos) {
            pthread_cond_wait(&processor->worker_cond, &processor->worker_mutex);
        }
        tail = processor.input_pos;
        pthread_mutex_unlock(&processor->worker_mutex);
        
        if (tail == -1) {
            return NULL;
        }
        
        while (true) {
            head = (head + 1) % processor.input_size;
            if (head == tail) {
                head = prev_head;
                break;
            }
            frames++;
            
            // If we have enough frames for an FFT or we have
            // all frames required for the interval run and FFT.
            bool int_full =
            acc_error < processor.file->get_error_base() &&
            frames == processor.file->get_frames_per_interval();
            bool int_over =
            acc_error >= processor.file->get_error_base() &&
            frames == 1 + processor.file->get_frames_per_interval();
            
            if (frames % processor.nfft == 0 || ((int_full || int_over) && num_fft == 0)) {
                prev_head = head;
                for (int i = 0; i < processor.nfft; i++) {
                    float val = processor.input[(processor.input_size + head - processor.nfft + i) % processor.input_size];
                    val *= [processor getWindowAtIndexOfCosTable:i];
                    processor.fft->set_input(i, val);
                }
                processor.fft->execute();
                num_fft++;
                for (int i = 0; i < processor.fft->get_output_size(); i++) {
                    processor.output[i] += processor.fft->get_output(i);
                }
            }
            
            // Do we have the FFTs for one interval?
            if (int_full || int_over) {
                if (int_over) {
                    acc_error -= processor.file->get_error_base();
                } else {
                    acc_error += processor.file->get_error_per_interval();
                }
                
                for (int i = 0; i < processor.fft->get_output_size(); i++) {
                    processor.output[i] /= num_fft;
                }
                
                if (sample == processor.samples) break;
                [processor performSelectorOnMainThread:@selector(update) withObject:nil waitUntilDone:NO];
//                p->cb(p->fft->get_output_size(), sample++, p->output, p->cb_data);
                
                memset(processor.output, 0, sizeof(float) * processor.fft->get_output_size());
                frames = 0;
                num_fft = 0;
            }
        }
    }
}

- (float)getWindowAtIndexOfCosTable:(NSInteger)index {
    switch (self.window) {
        case WINDOW_HANN:
            return 0.5f * (1.0f - self.coss[index]);
        case WINDOW_HAMMING:
            return 0.53836f - 0.46164f * self.coss[index];
        case WINDOW_BLACKMAN_HARRIS:
            return 0.35875f - 0.48829f * self.coss[index]
                            + 0.14128f * self.coss[2 * index % self.nfft]
                            - 0.01168f * self.coss[3 * index % self.nfft];
        default:
            assert(false);
            return 0.0f;
    }
}

#pragma mark -
#pragma mark Get Properties
- (NSString *)description {
    return nil;
}

- (NSUInteger)streams {
    return self.file->get_streams();
}

- (NSUInteger)channels {
    return self.file->get_channels();
}

- (double)duration {
    return self.file->get_duration();
}

- (NSUInteger)sampleRate {
    return self.file->get_sample_rate();
}
*/

- (void)update {
    static int ii = 0;
    NSLog(@"%@-%d", @"Updated", ++ii);
}

@end

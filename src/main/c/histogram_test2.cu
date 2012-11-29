#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

#include <GL/glut.h>
#include <cuda_gl_interop.h>
#include <cuda_runtime_api.h>

#define numBins 10
#define width 1000
#define height 1000

#define dimBlockx 16
#define dimBlocky 16

cudaArray *cuArray;
float* imageData;
int* dBins;
int* hBins;

int gridX;
int gridY;
int sizeBins;

// a reference to a 2D texture where each texture element contains a 1D float value
// cudaReadModeElementType specifies that the returned data value should not be normalized
texture<float,  2, cudaReadModeElementType> texture_float_2D;

// clamp
inline __device__ float clamp(float f, float a, float b)
{
    return fmaxf(a, fminf(f, b));
}

// bins     global memory vector to be filled with bin counts
// nbins    size of bins vector
// minX     the minimum x texture coordinate
// stepX    step size in x in texture coordinates
// minY     the minimum y texture coordinate
// stepY    step size in y in texture coordinates
// minZ     data value of the left edge of the left-most bin
// maxZ     data value of the right edge of the right-most bin
extern "C" __global__ void calculateHistogram2( int* bins,
                                                float minX, float stepX,
                                                float minY, float stepY,
                                                float minZ, float maxZ )
{
    __shared__ int localBins[numBins];

    int tid = threadIdx.x + threadIdx.y * blockDim.y;
    int bid = blockIdx.x + blockIdx.y * gridDim.y;

    // use block and thread ids to get texture coordinates for this thread
    int i = blockIdx.x * blockDim.x + threadIdx.x;
    int j = blockIdx.y * blockDim.y + threadIdx.y;

    // convert block/thread ids into texture coordinates
    float x = minX + stepX * i;
    float y = minY + stepY * j;

    // clear the shared memory bins (only the first numBins threads)
    if ( tid < numBins )
    {
        localBins[tid] = 0;
    }

    // don't over count if texture coordinates are out of bounds
    if ( x < 1.0 && y < 1.0 )
    {
        // perform texture lookup
        float result = tex2D(texture_float_2D, x, y);
    
        // calculate bin index
        float stepZ = ( maxZ - minZ ) / numBins;
        float fbinIndex = floor( ( result - minZ ) / stepZ );
        int binIndex = (int) clamp( fbinIndex, 0, numBins-1 );
    
        // atomically add one to the bin corresponding to the data value
        atomicAdd( localBins+binIndex, 1 );
    }

    // wait for all threads in this block to finish incrementing their bin
    __syncthreads();

    // the first numBins threads each write out one shared bin to global memory
    if ( tid < numBins )
    {
        bins[bid*numBins+tid] = localBins[tid];
    }
}

void initImageData( float* data )
{
    int w,h;

    float pi = atan(1) * 4;

    for ( w = 0; w < width; w++ )
    {
        for ( h = 0; h < height; h++ )
        {
            float x = w / ( float ) width;
            float y = h / ( float ) height;

            float r = rand() / (float) RAND_MAX;
            data[h+w*height] = ( y * y + sin( 2 * pi * x * x ) + r ) * 100;
        }
    }
}

void init(int argc, char **argv)
{
    // size of texture data
    unsigned int size = width * height * sizeof(float);

    // allocate space for texture data and initialize with interesting function
    imageData = (float*) malloc( size );
    initImageData( imageData );

    // set up CUDA texture description (32 bit float)
    cudaChannelFormatDesc channelDesc = cudaCreateChannelDesc(32, 0, 0, 0, cudaChannelFormatKindFloat);

    // create a CUDA array for accessing texture data
    cudaMallocArray(&cuArray,&channelDesc,width,height);

    // copy image data from the host into the CUDA array
    cudaMemcpyToArray(cuArray, 0, 0, imageData, size, cudaMemcpyHostToDevice);

    // set texture access modes for the CUDA texture variable
    // (clamp access for texture coordinates outside 0 to 1)
    texture_float_2D.addressMode[0] = cudaAddressModeClamp;
    texture_float_2D.addressMode[1] = cudaAddressModeClamp;
    texture_float_2D.filterMode = cudaFilterModeLinear;
    texture_float_2D.normalized = true;    // access with normalized texture coordinates

    // bind the array to the texture
    cudaBindTextureToArray(texture_float_2D, cuArray, channelDesc);
    
    // calculate block and grid dimensions
    gridX = ceil( width / (float) dimBlockx );
    gridY = ceil( height / (float) dimBlocky );

    // allocate space for histogram bin results
    // we allocate a set of bins *for each block*
    sizeBins = sizeof( int ) * numBins * gridX * gridY;
    hBins = (int*) malloc( sizeBins );
    cudaMalloc( &dBins, sizeBins );
}

void calculateHistogram(void)
{
    // clearing global memory is no longer necessary
    // because the values placed here are copied from
    // shared memory in the kernel (however, those shared
    // memory locations must be zeroed out)
    //cudaMemset( dBins, 0, sizeBins );

    // calculate block and grid dimensions
    dim3 dimBlock( dimBlockx, dimBlocky, 1);
    dim3 dimGrid( gridX, gridY, 1);

    // run the kernel over the whole texture
    float stepX = 1.0 / width;
    float stepY = 1.0 / height;
    float minZ = -50.0;
    float maxZ = 200.0;
    calculateHistogram2<<<dimGrid, dimBlock>>>( dBins, 0, stepX, 0, stepY, minZ, maxZ );

    // copy results back to host
    cudaMemcpy( hBins, dBins, sizeBins, cudaMemcpyDeviceToHost );

    // allocate space for accumulated bin counts
    int finalBins[numBins];
    int i,j,k;
    for ( i = 0 ; i < numBins ; i++ )
    {
        finalBins[i] = 0;
    }

    // collate results from each gpu block on cpu
    for ( i = 0 ; i < gridX ; i++ )
    {
        for ( j = 0 ; j < gridY ; j++ )
        {
            int bid = i + j * gridY;
            for ( k = 0 ; k < numBins ; k++ )
            {
                printf( "%d %d %d %d\n", i, j, k, hBins[bid+k] );
                finalBins[k] += hBins[bid+k];
            }
        }
    }

    // print results
    for ( i = 0 ; i < numBins ; i++ )
    {
        printf( "%d\n", finalBins[i] );
    }
}

//Main program
int main(int argc, char **argv)
{
  printf("CUDA Histogram Calculator\n");

  init( argc, argv );

  calculateHistogram( );

  free( hBins );
  free( imageData );

  cudaFree(dBins);
  cudaFreeArray(cuArray);

  return 0;
}

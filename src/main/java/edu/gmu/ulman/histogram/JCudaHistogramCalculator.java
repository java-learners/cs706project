package edu.gmu.ulman.histogram;

import static jcuda.driver.JCudaDriver.cuCtxCreate;
import static jcuda.driver.JCudaDriver.cuDeviceGet;
import static jcuda.driver.JCudaDriver.cuGraphicsGLRegisterImage;
import static jcuda.driver.JCudaDriver.cuGraphicsMapResources;
import static jcuda.driver.JCudaDriver.cuGraphicsSubResourceGetMappedArray;
import static jcuda.driver.JCudaDriver.cuInit;
import static jcuda.driver.JCudaDriver.cuModuleLoad;

import java.io.IOException;

import jcuda.driver.CUarray;
import jcuda.driver.CUcontext;
import jcuda.driver.CUdevice;
import jcuda.driver.CUgraphicsResource;
import jcuda.driver.CUmodule;
import jcuda.driver.JCudaDriver;
import jcuda.runtime.JCuda;
import jcuda.runtime.cudaGraphicsRegisterFlags;
import edu.gmu.ulman.histogram.util.PtxUtils;

public class JCudaHistogramCalculator
{
    private CUdevice dev;
    private CUcontext pctx;
    private CUmodule module;
    private CUgraphicsResource pres;
    private CUarray parray;
    private int texHandle;

    /**
     * Initialize the CUDA driver.
     * 
     * @param texHandle OpenGL texture handle
     * @throws IOException 
     */
    public void initialize( int texHandle ) throws IOException
    {
        // Enable exceptions and omit all subsequent error checks
        JCudaDriver.setExceptionsEnabled( true );

        // initialize the CUDA driver API, passing in no argument flags
        cuInit( 0 );

        // get a handle to the first GPU device
        // (arguments of >1 allow for the possibility of multi-gpu systems)
        dev = new CUdevice( );
        cuDeviceGet( dev, 0 );

        // create a CUDA context and associate it with the current thread
        // no argument flags means the default strategy will be used for
        // scheduling the OS thread that the CUDA context is current on while
        // waiting for results from the GPU. The default strategy is CU_CTX_SCHED_AUTO.
        //
        // From the JCUDA Javadocs, CU_CTX_SCHED_AUTO indicates:
        //
        // a heuristic based on the number of active CUDA contexts in the process C and
        // the number of logical processors in the system P. If C > P, then CUDA will
        // yield to other OS threads when waiting for the GPU, otherwise CUDA will not
        // yield while waiting for results and actively spin on the processor.
        pctx = new CUcontext( );
        cuCtxCreate( pctx, 0, dev );

        // Load the file containing kernels for calculating histogram values on the GPU into a CUmodule
        String ptxFileName = PtxUtils.preparePtxFile( "src/main/java/resources/HistogramTexureKernel.cu" );
        module = new CUmodule( );
        cuModuleLoad( module, ptxFileName );

        // create a cudaGraphicsResource which allows CUDA kernels to access OpenGL textures
        // http://developer.download.nvidia.com/compute/cuda/4_2/rel/toolkit/docs/online/group__CUDA__TYPES_gc0c4e1704647178d9c5ba3be46517dcd.html
        this.texHandle = texHandle;
        CUgraphicsResource pres = new CUgraphicsResource( );
        // JCuda.cudaTextureType2D = GL_TEXTURE_2D and indicates the texture is a 2D texture
        // cudaGraphicsRegisterFlags.cudaGraphicsRegisterFlagsReadOnly indicates CUDA will only read from the texture
        cuGraphicsGLRegisterImage( pres, texHandle, JCuda.cudaTextureType2D, cudaGraphicsRegisterFlags.cudaGraphicsRegisterFlagsReadOnly );

        // create a cuArray object which will be used to access OpenGL texture data via CUDA
        parray = new CUarray( );

        // map the cuGraphicsResource, which makes it accessible to CUDA
        // (OpenGL should not access the texture until we unmap)
        cuGraphicsMapResources( 1, new CUgraphicsResource[] { pres }, null );

        // associate the cuArray with the cuGraphicsResource
        cuGraphicsSubResourceGetMappedArray( parray, pres, 0, 0 );
    }
}
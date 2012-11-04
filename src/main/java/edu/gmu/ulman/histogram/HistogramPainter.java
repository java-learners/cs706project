package edu.gmu.ulman.histogram;

import static com.metsci.glimpse.util.logging.LoggerUtils.*;

import java.util.logging.Logger;

import javax.media.opengl.GL;
import javax.media.opengl.GLContext;

import com.metsci.glimpse.axis.Axis2D;
import com.metsci.glimpse.context.GlimpseBounds;
import com.metsci.glimpse.painter.base.GlimpseDataPainter2D;

public class HistogramPainter extends GlimpseDataPainter2D
{
    private static final Logger logger = Logger.getLogger( HistogramPainter.class.getName( ) );

    AccessibleFloatTexture2D texture;
    JCudaHistogramCalculator calculator;
    
    private double minValue;
    private double maxValue;
    private int numBins;

    public HistogramPainter( AccessibleFloatTexture2D texture, int numBins, double minValue, double maxValue )
    {
        this.texture = texture;
        
        this.numBins = numBins;
        this.minValue = minValue;
        this.maxValue = maxValue;
    }

    @Override
    public void paintTo( GL gl, GlimpseBounds bounds, Axis2D axis )
    {
        // check if the opengl texture handle has been allocated
        // if not, do nothing until it is
        if ( calculator == null )
        {
            int[] handles = texture.getTextureHandles( );
            if ( handles == null || handles.length == 0 || handles[0] <= 0 ) return;

            calculator = new JCudaHistogramCalculator( numBins, minValue, maxValue );

            try
            {
                calculator.initialize( handles[0] );
            }
            catch ( Exception e )
            {
                logWarning( logger, "Trouble initializing JCudaHistogramCalculator (CUDA)", e );
                calculator = null;
            }
        }

        if ( calculator != null )
        {
            calculator.calculateHistogram( );
        }
    }

    @Override
    protected void dispose( GLContext context )
    {
        calculator.dispose( context );
    }
}

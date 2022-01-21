/*
  Based on reference QOI reference implementation: https://github.com/phoboslab/qoi/blob/master/qoi.h
  (by Dominic Szablewski - https://phoboslab.org)
  Ported by aquaratixc (Oleg Bakharev) and LightHouse Software (lhs-blog.info)
  
  Written in D programming language
*/
module qoiformats;

private {
	import core.stdc.stdio;
	import core.stdc.stdlib : free, malloc;
	import core.stdc.string : memset;
	
	import std.algorithm : clamp;
	import std.conv : to;
	import std.string : format, toLower;
		
	template addProperty(T, string propertyName, string defaultValue = T.init.to!string)
	{	 
		const char[] addProperty = format(
			`
			private %2$s %1$s = %4$s;
	 
			void set%3$s(%2$s %1$s)
			{
				this.%1$s = %1$s;
			}
	 
			%2$s get%3$s()
			{
				return %1$s;
			}
			`,
			"_" ~ propertyName.toLower,
			T.stringof,
			propertyName,
			defaultValue
			);
	}
	
	enum QOI_CHANNELS : ubyte
	{
		RGB  = 3,
		RGBA = 4
	};
	
	enum QOI_COLORSPACE : ubyte
	{
		SRGB   = 0,
		LINEAR = 1
	};
	
	class QoiImageInfo
	{
		mixin(addProperty!(uint, "Width"));
		mixin(addProperty!(uint, "Height"));
		mixin(addProperty!(QOI_CHANNELS, "Channels", "QOI_CHANNELS.RGB"));
		mixin(addProperty!(QOI_COLORSPACE, "Colorspace", "QOI_COLORSPACE.SRGB"));
		
		this(
			uint width = 0, 
			uint height = 0, 
			QOI_CHANNELS channels = QOI_CHANNELS.RGB, 
			QOI_COLORSPACE colorspace = QOI_COLORSPACE.SRGB
		)
		{
			_width = width;
			_height = height;
			_channels = channels;
			_colorspace = colorspace;
		}
		
		override string toString()
		{		
			return format(
				"QoiImageInfo(width = %d, height = %d, channels = %s, colorspace = %s)", 
				_width,
				_height,
				_channels.to!string,
				_colorspace.to!string
			);
		}
	}
	
	class QoiOperation
	{
		static void write32(ubyte* bytes, int* p, uint v)
		{
			bytes[(*p)++] = (0xff000000 & v) >> 24;
			bytes[(*p)++] = (0x00ff0000 & v) >> 16;
			bytes[(*p)++] = (0x0000ff00 & v) >> 8;
			bytes[(*p)++] = (0x000000ff & v);
		}
		
		static uint read32(ubyte* bytes, int* p)
		{
			uint a = bytes[(*p)++];
			uint b = bytes[(*p)++];
			uint c = bytes[(*p)++];
			uint d = bytes[(*p)++];
			return (
				(a << 24) | (b << 16) | (c << 8) | d
			);
		}
		
		static uint hash32(RGBA rgba) 
		{
			return rgba.r * 3 + rgba.g * 5 + rgba.b * 7 + rgba.a * 11;
		}
	}
		
	enum QOI_OP : ubyte
	{
		INDEX =  0x00,
		DIFF  =  0x40,
		LUMA  =  0x80,
		RUN   =  0xc0,
		RGB   =  0xfe, 
		RGBA  =  0xff 
	}
	
	enum ubyte QOI_MASK_2 = 0xc0;
	
	enum uint QOI_MAGIC = (
		(cast(uint) 'q') << 24 | 
		(cast(uint) 'o') << 16 | 
		(cast(uint) 'i') <<  8 | 
		(cast(uint) 'f')
	);
	
	enum ubyte QOI_HEADER_SIZE = 14;

	enum uint QOI_PIXELS_MAX = cast(uint) 400_000_000;
	
	static ubyte[8] QOI_PADDING = [0, 0, 0, 0, 0, 0, 0, 1];
	
	union RGBA {
		struct {ubyte r, g, b, a; };
		uint v;
	}
}

class QoiColor
{
	private
	{
		RGBA _rgba;
	}
	
	this(ubyte R = 0, ubyte G = 0, ubyte B = 0, ubyte A = 0)
	{
		_rgba.r = R;
		_rgba.g = G;
		_rgba.b = B;
		_rgba.a = A;
	}
	
	ubyte getR()
	{
		return _rgba.r;
	}
	
	ubyte getG()
	{
		return _rgba.g;
	}
	
	ubyte getB()
	{
		return _rgba.b;
	}
	
	ubyte getA()
	{
		return _rgba.a;
	}
	
	void setR(ubyte r)
	{
		_rgba.r = r;
	}
	
	void setG(ubyte g)
	{
		_rgba.g = g;
	}
	
	void setB(ubyte b)
	{
		_rgba.b = b;
	}
	
	void setA(ubyte a)
	{
		_rgba.a = a;
	}
	
	RGBA get()
	{
		return _rgba;
	}
	
	const float luminance709()
	{
	   return (_rgba.r  * 0.2126f + _rgba.g  * 0.7152f + _rgba.b  * 0.0722f);
	}
	
	const float luminance601()
	{
	   return (_rgba.r * 0.3f + _rgba.g * 0.59f + _rgba.b * 0.11f);
	}
	
	const float luminanceAverage()
	{
	   return (_rgba.r + _rgba.g + _rgba.b) / 3.0;
	}

	alias luminance = luminance709;

	override string toString()
	{		
		return format(
			"QoiColor(%d, %d, %d, %d, I = %f)", 
			_rgba.r, _rgba.g, _rgba.b, _rgba.a, this.luminance
		);
	}

	QoiColor opBinary(string op, T)(auto ref T rhs)
	{
		return mixin(
			format(`new QoiColor( 
				cast(ubyte) clamp((_rgba.r %1$s rhs), 0, 255),
				cast(ubyte) clamp((_rgba.g %1$s rhs), 0, 255),
				cast(ubyte) clamp((_rgba.b %1$s rhs), 0, 255),
				cast(ubyte) clamp((_rgba.a %1$s rhs), 0, 255)
				)
			`,
			op
			)
		);
	}
	
	QoiColor opBinary(string op)(QoiColor rhs)
	{
		return mixin(
			format(`new QoiColor( 
				cast(ubyte) clamp((_rgba.r %1$s rhs.getR), 0, 255),
				cast(ubyte) clamp((_rgba.g %1$s rhs.getG), 0, 255),
				cast(ubyte) clamp((_rgba.b %1$s rhs.getB), 0, 255),
				cast(ubyte) clamp((_rgba.a %1$s rhs.getA), 0, 255)
				)
			`,
			op
			)
		);
	}
	
	alias get this; 
}

class QoiImage
{
	private
	{
		QoiColor[]   _image;
		QoiImageInfo  _info;
	}
	
	private
	{
		auto actualIndex(uint i)
		{
			auto S = _info.getWidth * _info.getHeight;
		
			return clamp(i, 0, S - 1);
		}

		auto actualIndex(uint i, uint j)
		{
			auto W = cast(uint) clamp(i, 0, this.getWidth - 1);
			auto H = cast(uint) clamp(j, 0, this.getHeight - 1);
			auto S = this.getArea;
		
			return clamp(W + H * this.getWidth, 0, S);
		}
		
		void* encode(void* data, QoiImageInfo info, int* outputLength) 
		{
			RGBA[64] index;
			RGBA px, pxPrevious;
			int i, maximalSize, p, run;
			int pxLength, pxEnd, pxPosition, channels;
			ubyte* bytes, pixels;
		
		
			if (
				(data is null) || (outputLength is null) || (info is null) ||
				(info.getWidth == 0) || (info.getHeight == 0) ||
				(info.getChannels < 3) || (info.getChannels > 4 ) ||
				(info.getColorspace > 1) ||
				(info.getHeight >= QOI_PIXELS_MAX / info.getWidth)
			) {
				return null;
			}
		
			maximalSize = cast(int) (
				info.getWidth * info.getHeight * (info.getChannels + 1) +
				QOI_HEADER_SIZE + QOI_PADDING.length
			);
		
			p = 0;
			bytes = cast(ubyte*) malloc(maximalSize);
			if (!bytes) 
			{
				return null;
			}
		
			QoiOperation.write32(bytes, &p, QOI_MAGIC);
			QoiOperation.write32(bytes, &p, info.getWidth);
			QoiOperation.write32(bytes, &p, info.getHeight);
			bytes[p++] = cast(byte) info.getChannels;
			bytes[p++] = cast(byte) info.getColorspace;
		
			pixels = cast(ubyte*) data;
		
			memset(index.ptr, 0, index.length);
		
			run = 0;
			with (pxPrevious)
			{
				r = 0;
				g = 0;
				b = 0;
				a = 255;
			}
			px = pxPrevious;
		
			pxLength = info.getWidth * info.getHeight * info.getChannels;
			pxEnd = pxLength - info.getChannels;
			channels = info.getChannels;
		
			for (pxPosition = 0; pxPosition < pxLength; pxPosition += channels) 
			{
				if (channels == 4) 
				{
					px = *(cast(RGBA*)(pixels + pxPosition));
				}
				else 
				{
					with (px)
					{
						r = pixels[pxPosition + 0];
						g = pixels[pxPosition + 1];
						b = pixels[pxPosition + 2];
					}
				}
		
				if (px.v == pxPrevious.v) {
					run++;
					if (run == 62 || pxPosition == pxEnd) {
						bytes[p++] = cast(ubyte) (QOI_OP.RUN | (run - 1));
						run = 0;
					}
				}
				else {
					int index_pos;
		
					if (run > 0) {
						bytes[p++] = cast(ubyte) (QOI_OP.RUN | (run - 1));
						run = 0;
					}
		
					index_pos = QoiOperation.hash32(px) % 64;
		
					if (index[index_pos].v == px.v) {
						bytes[p++] = cast(byte) (QOI_OP.INDEX | index_pos);
					}
					else {
						index[index_pos] = px;
		
						if (px.a == pxPrevious.a) {
							byte vr = cast(byte) (px.r - pxPrevious.r);
							byte vg = cast(byte) (px.g - pxPrevious.g);
							byte vb = cast(byte) (px.b - pxPrevious.b);
							
							byte vg_r = cast(byte) (vr - vg);
							byte vg_b = cast(byte) (vb - vg);
		
							if (
								(vr > -3) && (vr < 2) &&
								(vg > -3) && (vg < 2) &&
								(vb > -3) && (vb < 2)
							) {
								bytes[p++] = cast(byte) (QOI_OP.DIFF | (vr + 2) << 4 | (vg + 2) << 2 | (vb + 2));
							}
							else if (
								(vg_r >  -9) && (vg_r <  8) &&
								(vg   > -33) && (vg   < 32) &&
								(vg_b >  -9) && (vg_b <  8)
							) {
								bytes[p++] = cast(byte) (QOI_OP.LUMA     | (vg   + 32));
								bytes[p++] = cast(byte) ((vg_r + 8) << 4 | (vg_b +  8));
							}
							else {
								bytes[p++] = QOI_OP.RGB;
								with (px)
								{
									bytes[p++] = r;
									bytes[p++] = g;
									bytes[p++] = b;
								}
							}
						}
						else {
							bytes[p++] = QOI_OP.RGBA;
							with (px)
							{
								bytes[p++] = r;
								bytes[p++] = g;
								bytes[p++] = b;
								bytes[p++] = a;
							}
						}
					}
				}
				pxPrevious = px;
			}
		
			for (i = 0; i < cast(int) QOI_PADDING.length; i++) 
			{
				bytes[p++] = QOI_PADDING[i];
			}
		
			*outputLength = p;
			return bytes;
		}
		
		void* decode(void* data, int size, QoiImageInfo info, int channels)
		{
			RGBA[64] index;
			RGBA px;
			ubyte* bytes, pixels;
			uint headerMagic;
			int p, run, pxLength, chunksLength, pxPosition;
		
			if (
				(data is null) || 
				(info is null) ||  
				(channels != 0 && channels != 3 && channels != 4) ||
			    (size < QOI_HEADER_SIZE + cast(int) QOI_PADDING.length)
			) 
			{
				return null;
			}
		
			bytes = cast(ubyte*) data;
		
			headerMagic = QoiOperation.read32(bytes, &p);
			
			with (info)
			{
				setWidth = QoiOperation.read32(bytes, &p);
				setHeight = QoiOperation.read32(bytes, &p);
				setChannels = cast(QOI_CHANNELS) bytes[p++];
				setColorspace = cast(QOI_COLORSPACE) bytes[p++];
			}
		
			if (
				(info.getWidth == 0)  || 
				(info.getHeight == 0) ||
				(info.getChannels < 3)   || 
				(info.getChannels > 4) ||
				(info.getColorspace > 1) ||
				(headerMagic != QOI_MAGIC) ||
				(info.getHeight >= QOI_PIXELS_MAX / info.getWidth)
			) 
			{
				return null;
			}
		
			if (channels == 0) 
			{
				channels = info.getChannels;
			}
		
			pxLength = info.getWidth * info.getHeight * channels;
			pixels = cast(ubyte*) malloc(pxLength);
			
			if (!pixels) 
			{
				return null;
			}
		
			memset(index.ptr, 0, index.length);
			
			with (px)
			{
				r = 0;
				g = 0;
				b = 0;
				a = 255;
			}
		
			chunksLength = size - cast(int) QOI_PADDING.length;
			
			for (pxPosition = 0; pxPosition < pxLength; pxPosition += channels) 
			{
				if (run > 0) 
				{
					run--;
				}
				else if (p < chunksLength) {
					int b1 = bytes[p++];
		
					if (b1 == QOI_OP.RGB) {
						with (px)
						{
							r = bytes[p++];
							g = bytes[p++];
							b = bytes[p++];
						}
					}
					else if (b1 == QOI_OP.RGBA) {
						with (px)
						{
							r = bytes[p++];
							g = bytes[p++];
							b = bytes[p++];
							a = bytes[p++];
						}
					}
					else if ((b1 & QOI_MASK_2) == QOI_OP.INDEX) {
						px = index[b1];
					}
					else if ((b1 & QOI_MASK_2) == QOI_OP.DIFF) {
						with (px)
						{
							r += ((b1 >> 4) & 0x03) - 2;
							g += ((b1 >> 2) & 0x03) - 2;
							b += ( b1       & 0x03) - 2;
						}
					}
					else if ((b1 & QOI_MASK_2) == QOI_OP.LUMA) {
						int b2 = bytes[p++];
						int vg = (b1 & 0x3f) - 32;
						with (px)
						{
							r += vg - 8 + ((b2 >> 4) & 0x0f);
							g += vg;
							b += vg - 8 +  (b2       & 0x0f);
						}
					}
					else if ((b1 & QOI_MASK_2) == QOI_OP.RUN) {
						run = (b1 & 0x3f);
					}
		
					index[QoiOperation.hash32(px) % 64] = px;
				}
		
				if (channels == 4) 
				{
					*(cast(RGBA*)(pixels + pxPosition)) = px;
				}
				else 
				{
					with (px)
					{
						pixels[pxPosition + 0] = r;
						pixels[pxPosition + 1] = g;
						pixels[pxPosition + 2] = b;
					}
				}
			}
		
			return pixels;
		}
		
		
		void* read(char* filename, QoiImageInfo info, int channels) 
		{
			int size, bytesRead;
			void* pixels, data;
			
			FILE* f = fopen(filename, "rb");
			if (!f) 
			{
				return null;
			}
		
			fseek(f, 0, SEEK_END);
			size = cast(int) ftell(f);
			
			if (size <= 0) 
			{
				fclose(f);
				return null;
			}
			
			fseek(f, 0, SEEK_SET);
		
			data = malloc(size);
			
			if (!data) 
			{
				fclose(f);
				return null;
			}
		
			bytesRead = cast(int) fread(data, 1, size, f);
			fclose(f);
		
			pixels = decode(data, bytesRead, info, channels);
			free(data);
			
			return pixels;
		}
		
		int write(const char *filename, void* data, QoiImageInfo info) 
		{
			int size;
			void* encoded;
			
			FILE* f = fopen(filename, "wb");
			if (!f) 
			{
				return 0;
			}
		
			encoded = encode(data, info, &size);
			if (!encoded) 
			{
				fclose(f);
				return 0;
			}
		
			fwrite(encoded, 1, size, f);
			fclose(f);
		
			free(encoded);
			return size;
		}
	}
	
	this(
		uint width = 0, 
		uint height = 0, 
		QoiColor color = new QoiColor(0, 0, 0),
		QOI_CHANNELS channels = QOI_CHANNELS.RGB, 
		QOI_COLORSPACE colorspace = QOI_COLORSPACE.SRGB
	)
	{
		_info = new QoiImageInfo(width, height, channels, colorspace);
		
		foreach (x; 0..width)
		{
			foreach (y; 0..height)
			{
				_image ~= color;
			}	
		}
	}
	
	// image width
	uint getWidth()
	{
		return _info.getWidth;
	}
	
	// image height
	uint getHeight()
	{
		return _info.getHeight;
	}
	
	// image area
	uint getArea()
	{
		return _info.getWidth * _info.getHeight;
	}
	
	// image as array
	QoiColor[] getImage()
	{
		return _image;
	}
	
	// image info
	QoiImageInfo getInfo()
	{
		return _info;
	}
	
	// img[x, y] = color
	QoiColor opIndexAssign(QoiColor color, uint x, uint y)
	{
		_image[actualIndex(x, y)] = color;
		return color;
	}

	// img[x] = color
	QoiColor opIndexAssign(QoiColor color, uint x)
	{
		_image[actualIndex(x)] = color;
		return color;
	}

	// img[x, y]
	QoiColor opIndex(uint x, uint y)
	{
		return _image[actualIndex(x, y)];
	}

	// img[x]
	QoiColor opIndex(uint x)
	{
		return _image[actualIndex(x)];
	}

	// image as string
	override string toString()
	{
		string accumulator = "[";

		foreach (x; 0..this.getWidth)
		{
			string tmp = "[";
			foreach (y; 0..this.getHeight)
			{
				tmp ~= _image[actualIndex(x, y)].toString ~ ", ";				
			}
			tmp = tmp[0..$-2] ~ "], ";
			accumulator ~= tmp;
		}
		return accumulator[0..$-2] ~ "]";
	}
	
	// load QOI file
	void load(string filename)
	{
		char* name = cast(char*) filename.ptr;
		void* data = read(name, _info, 0);
		
		if (data !is null)
		{
			auto channels = _info.getChannels;
			auto squared = this.area * channels;
			
			for (uint i = 0; i < squared; i += channels)
			{
				QoiColor rgba;
				
				final switch (channels) with (QOI_CHANNELS)
				{
					case RGB:
						auto q = cast(ubyte[]) data[i..i+3];
						rgba = new QoiColor(q[0], q[1], q[2]);
						break;
					case RGBA:
						auto q = cast(ubyte[]) data[i..i+4];
						rgba = new QoiColor(q[0], q[1], q[2], q[3]);
						break;
				}
				
				_image ~= rgba;
			}
		}
	}
	
	// save QOI file
	void save(string filename)
	{
		char* name = cast(char*) filename.ptr;
		auto channels = _info.getChannels;
		auto squared = this.area;
		
		ubyte[] data;
		
		for (uint i = 0; i < squared; i++)
		{
			auto q = _image[i];
			final switch (channels) with (QOI_CHANNELS)
			{
				case RGB:
					data ~= [q.getR, q.getG, q.getB];
					break;
				case RGBA:
					data ~= [q.getR, q.getG, q.getB, q.getA];
					break;
			}
		}
		
		write(name, cast(void*) data.ptr, _info);
	}
	
	
	// aliases
	alias width = getWidth;
	alias height = getHeight;
	alias area = getArea;
	alias image = getImage;
	alias info = getInfo;
}

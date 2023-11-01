#import "Array";
#import "Hash_Map";
#import "freetype-2.12.1";

Default_Glyph_Atlas_Width  :: 1024;
Default_Glyph_Atlas_Height :: 1024;

Font :: struct
{
    filename : string;
    ft_face : FT_Face;
    pages : HashMap (u32, FontPage);
}

// @Todo: optimize for ASCII/Latin

FontPage :: struct
{
    font : *Font;
    height : u32;
    atlases : [..]GlyphAtlas;
    glyphs : HashMap (u32, Glyph);
    ascent, descent : s32;
    space_advance : u32;    // Advance of the space glyph
}

Glyph :: struct
{
    codepoint : u32;

    rendered : bool;
    width, height : u32;
    bearing_x, bearing_y : s32;
    advance : u32;
    bitmap_width, bitmap_height : u32;
    bitmap_left, bitmap_top : s32;

    uv_rect : Rect;
    atlas_texture : TextureHandle;
}

GlyphAtlas :: struct
{
    texture : TextureHandle;
    width, height : u32;
    pen_x, pen_y : s32;
    row_end : s32;
}

OverflowBehavior :: enum
{
    None;
    Clip;   // @Todo
    Wrap;
    Wrap_Word; // @Todo
}

#add_context stylo_font : *Font;

GetFont :: inline () -> *Font #must
{
    return context.stylo_font;
}

SetFont :: inline (font : *Font)
{
    context.stylo_font = font;
}

#scope_file

g_ft_lib : FT_Library;

InitFonts :: () -> bool
{
    ft_err := FT_Init_FreeType (*g_ft_lib);
    if ft_err != xx FT_Err.Ok
    {
        LogError ("Could not intialize FreeType");
        return false;
    }

    return true;
}

#scope_export

LoadFontFromFile :: (filename : string) -> *Font #must
{
    if !g_ft_lib && !InitFonts ()
        return null;

    ft_face : FT_Face;
    ft_err := FT_New_Face (g_ft_lib, StringCloneToCString (filename, Temp), 0, *ft_face);
    if ft_err != xx FT_Err.Ok
        return null;

    font := Alloc (Font);
    font.filename = filename;
    font.ft_face = ft_face;
    font.pages.allocator = context.allocator;

    return font;
}

LoadFontPage :: (using font : *Font, height : u32) -> *FontPage
{
    page, exists := HashMapInsert (*pages, height);
    if exists
        return page;

    page.font = font;
    page.height = height;
    page.atlases.allocator = pages.allocator;
    HashMapInit (*page.glyphs, 512, pages.allocator);

    space_glyph := LoadGlyph (page, #char " ");
    page.ascent  = xx (ft_face.size.metrics.ascender >> 6);
    page.descent = xx (ft_face.size.metrics.descender >> 6);
    page.space_advance = xx (space_glyph.advance);

    return page;
}

AddGlyphAtlas :: (using page : *FontPage, atlas_width := Default_Glyph_Atlas_Width, atlas_height := Default_Glyph_Atlas_Height) -> *GlyphAtlas
{
    result := ArrayPush (*atlases);
    result.width = xx atlas_width;
    result.height = xx atlas_height;

    result.texture = CreateTexture (xx atlas_width, xx atlas_height, null);

    return result;
}

#scope_file

SetGlyphMetrics :: (glyph : *Glyph, slot : *FT_GlyphSlotRec)
{
    glyph.width = xx (slot.metrics.width >> 6);
    glyph.height = xx (slot.metrics.height >> 6);
    glyph.bearing_x = xx (slot.metrics.horiBearingX >> 6);
    glyph.bearing_y = xx (slot.metrics.horiBearingY >> 6);
    glyph.advance = xx (slot.metrics.horiAdvance >> 6);

    glyph.bitmap_width = xx slot.bitmap.width;
    glyph.bitmap_height = xx slot.bitmap.rows;
    glyph.bitmap_left = xx slot.bitmap_left;
    glyph.bitmap_top = xx slot.bitmap_top;
}

#scope_export

LoadGlyph :: (using page : *FontPage, codepoint : u32) -> *Glyph
{
    glyph, exists := HashMapInsert (*glyphs, codepoint);
    if exists
        return glyph;

    FT_Set_Pixel_Sizes (font.ft_face, 0, height);
    ft_error := FT_Load_Char (font.ft_face, codepoint, FT_LOAD_DEFAULT);
    Assert (ft_error == xx FT_Err.Ok);

    glyph.codepoint = codepoint;
    SetGlyphMetrics (glyph, font.ft_face.glyph);

    return glyph;
}

RenderGlyph :: (using page : *FontPage, codepoint : u32) -> *Glyph
{
    glyph, exists := HashMapInsert (*glyphs, codepoint);
    if exists && glyph.rendered
        return glyph;

    FT_Set_Pixel_Sizes (font.ft_face, 0, height);
    ft_error := FT_Load_Char (font.ft_face, codepoint, FT_LOAD_RENDER);
    Assert (ft_error == xx FT_Err.Ok);

    if !exists
    {
        glyph.codepoint = codepoint;
        SetGlyphMetrics (glyph, font.ft_face.glyph);
    }

    slot := font.ft_face.glyph;

    // @Todo: it seems to me that the criterias for selecting an atlas are wrong

    // Find an atlas to blit the glyph into
    atlas : *GlyphAtlas;
    for * atlases
    {
        if it.pen_x + xx glyph.bitmap_width <= xx it.width
        && it.pen_y + xx glyph.bitmap_height <= xx it.height
        {
            atlas = it;

            break;
        }
    }

    if !atlas
        atlas = AddGlyphAtlas (page);

    if atlas.pen_x + xx glyph.bitmap_width > xx atlas.width
    || atlas.pen_y + xx glyph.bitmap_height > xx atlas.height
    {
        atlas.pen_x = 0;
        atlas.pen_y = atlas.row_end;
        atlas.row_end += xx glyph.bitmap_height;
    }

    if glyph.bitmap_width > 0 && glyph.bitmap_height > 0
    {
        TemporaryStorageScope ();

        rgba_bitmap := Alloc (u32, glyph.bitmap_width * glyph.bitmap_height, Temp);
        for y : 0..glyph.bitmap_height - 1
        {
            for x : 0..glyph.bitmap_width - 1
            {
                index := x + y * glyph.bitmap_width;
                val := cast (u32) slot.bitmap.buffer[index];
                rgba_bitmap[index] = (val << 0) | (val << 8) | (val << 16) | (val << 24);
            }
        }

        BlitToTexture (
            atlas.texture,
            atlas.pen_x, atlas.pen_y,
            glyph.bitmap_width, glyph.bitmap_height,
            rgba_bitmap
        );
    }

    glyph.uv_rect = .{
        atlas.pen_x / cast (float) atlas.width,
        (atlas.pen_y + xx glyph.bitmap_height) / cast (float) atlas.height,
        glyph.bitmap_width / cast (float) atlas.width,
        -(glyph.bitmap_height / cast (float) atlas.height)
    };

    glyph.atlas_texture = atlas.texture;
    glyph.rendered = true;

    atlas.pen_x += xx glyph.bitmap_width;
    if atlas.pen_y + xx glyph.bitmap_height > atlas.row_end
        atlas.row_end = atlas.pen_y + xx glyph.bitmap_height;

    return glyph;
}

CalculateTextExtents :: inline (text : string, height : u32, rect : Rect, overflow : OverflowBehavior, font : *Font = null) -> Vec2f #must
{
    if !font
        font = context.stylo_font;

    page := LoadFontPage (font, height);

    return CalculateTextExtents (text, rect, overflow, page);
}

CalculateTextExtents :: (text : string, rect : Rect, overflow : OverflowBehavior, page : *FontPage) -> Vec2f #must
{
    pen := Vec2f.{0, cast (float) page.ascent};
    width : float;

    for codepoint, i : MakeUtf8String (text)
    {
        if codepoint ==
        {
        case #char "\n";
            width = Max (width, pen.x);
            pen.x = 0;
            pen.y += page.ascent - page.descent;

        case #char "\t";
            glyph := LoadGlyph (page, codepoint);
            pen.x = SnapUp (pen.x + glyph.advance, page.space_advance * 4.0);

            if overflow == .Wrap && pen.x > rect.w
            {
                pen.x = 0;
                pen.y += page.ascent - page.descent;
            }

            width = Max (width, pen.x);

        case;
            glyph := LoadGlyph (page, codepoint);

            if overflow == .Wrap && pen.x + glyph.bitmap_left > rect.w
            {
                pen.x = 0;
                pen.y += page.ascent - page.descent;
            }

            pen.x += glyph.advance;
            width = Max (width, pen.x);
        }
    }

    return .{width, pen.y - page.descent};
}

PushFormattedText :: (
    text : string,
    height : u32,
    rect : Rect,
    color := Vec4f.{1,1,1,1},
    align := Vec2f.{0,0},
    overflow := OverflowBehavior.None,
    font : *Font = null
) -> Rect
{
    if !font
        font = context.stylo_font;

    prev_texture := GetTexture ();
    defer SetTexture (prev_texture);

    page := LoadFontPage (font, height);
    pen := Vec2f.{0, cast (float) page.ascent};
    width : float;
    size := CalculateTextExtents (text, rect, overflow, page);
    offset := Vec2f.{
        rect.w * align.x - size.x * align.x,
        rect.h * align.y - size.y * align.y
    };

    for codepoint, i : MakeUtf8String (text)
    {
        if codepoint ==
        {
        case #char "\n";
            width = Max (width, pen.x);
            pen.x = 0;
            pen.y += page.ascent - page.descent;

        case #char "\t";
            glyph := LoadGlyph (page, codepoint);
            pen.x = SnapUp (pen.x + glyph.advance, page.space_advance * 4.0);

            if overflow == .Wrap && pen.x > rect.w
            {
                pen.x = 0;
                pen.y += page.ascent - page.descent;
            }

            width = Max (width, pen.x);

        case;
            glyph := RenderGlyph (page, codepoint);

            if overflow == .Wrap && pen.x + glyph.bitmap_left > rect.w
            {
                pen.x = 0;
                pen.y += page.ascent - page.descent;
            }

            #if Origin_Top_Left
            {
                glyph_rect := Rect.{
                    Round (rect.x + offset.x) + pen.x + glyph.bitmap_left,
                    Round (rect.y + offset.y) + pen.y - glyph.bitmap_top,
                    xx glyph.bitmap_width,
                    xx glyph.bitmap_height
                };
            }
            else
            {
                glyph_rect := Rect.{
                    Round (rect.x + offset.x) + pen.x + glyph.bitmap_left,
                    Round (rect.y + rect.h - offset.y) - pen.y + glyph.bitmap_top - glyph.bitmap_height,
                    xx glyph.bitmap_width,
                    xx glyph.bitmap_height
                };
            }

            pen.x += glyph.advance;
            width = Max (width, pen.x);

            SetTexture (glyph.atlas_texture);

            uv_rect := glyph.uv_rect;
            #if Origin_Top_Left
            {
                uv_rect.h = -uv_rect.h;
                uv_rect.y -= uv_rect.h;
            }

            PushRect (glyph_rect, color, uv_rect);
        }
    }

    #if Origin_Top_Left
        return .{Round (rect.x + offset.x), Round (rect.y + offset.y), size.x, size.y};
    else
        return .{Round (rect.x + offset.x), Round (rect.y + rect.h - size.y - offset.y), size.x, size.y};
}

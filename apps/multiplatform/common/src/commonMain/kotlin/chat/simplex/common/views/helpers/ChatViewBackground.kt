package chat.simplex.common.views.helpers

import androidx.compose.material.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntSize
import chat.simplex.common.platform.*
import chat.simplex.common.ui.theme.CurrentColors
import chat.simplex.common.ui.theme.DefaultTheme
import chat.simplex.res.MR
import dev.icerock.moko.resources.ImageResource
import dev.icerock.moko.resources.StringResource
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import kotlin.math.*

@Serializable
enum class PredefinedBackgroundImage(
  val res: ImageResource,
  val filename: String,
  val text: StringResource,
  val scale: Float,
  val background: Map<DefaultTheme, Color>,
  val tint: Map<DefaultTheme, Color>
) {
  @SerialName("cat") CAT(MR.images.background_cat, "simplex_cat", MR.strings.background_cat, 0.5f,
    mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
    mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("hearts") HEARTS(MR.images.background_hearts, "simplex_hearts", MR.strings.background_hearts, 0.5f,
    mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
    mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("school") SCHOOL(MR.images.background_school, "simplex_school",  MR.strings.background_school, 0.5f,
  mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
  mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("internet") INTERNET(MR.images.background_internet, "simplex_internet", MR.strings.background_internet, 0.5f,
  mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
  mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("space") SPACE(MR.images.background_space, "simplex_space", MR.strings.background_space, 0.5f,
  mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
  mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("pets") PETS(MR.images.background_pets, "simplex_pets", MR.strings.background_pets, 0.5f,
  mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
  mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  ),
  @SerialName("rabbit") RABBIT(MR.images.background_rabbit, "simplex_rabbit", MR.strings.background_rabbit, 0.5f,
  mapOf(DefaultTheme.LIGHT to Color.White, DefaultTheme.DARK to Color.Black, DefaultTheme.SIMPLEX to Color.Black),
  mapOf(DefaultTheme.LIGHT to Color.Blue, DefaultTheme.DARK to Color.Blue, DefaultTheme.SIMPLEX to Color.Blue)
  );

  fun toType(): BackgroundImageType =
    BackgroundImageType.Repeated(filename, scale)

  companion object {
    fun from(filename: String): PredefinedBackgroundImage? =
      entries.firstOrNull { it.filename == filename }
  }
}

@Serializable
enum class BackgroundImageScaleType(val contentScale: ContentScale, val text: StringResource) {
  @SerialName("fill") FILL(ContentScale.Crop, MR.strings.background_image_scale_fill),
  @SerialName("fit") FIT(ContentScale.Fit, MR.strings.background_image_scale_fit),
  @SerialName("repeat") REPEAT(ContentScale.Fit, MR.strings.background_image_scale_repeat),
}

@Serializable
sealed class BackgroundImageType {
  abstract val filename: String
  abstract val scale: Float

  val image by lazy {
    val cache = cachedImage
    if (cache != null && cache.first == filename) {
      cache.second
    } else {
      val res = if (this is Repeated) {
        PredefinedBackgroundImage.from(filename)!!.res.toComposeImageBitmap()!!
      } else {
        File(getBackgroundImageFilePath(filename)).inputStream().use { loadImageBitmap(it) }
      }
      cachedImage = filename to res
      res
    }
  }

  @Serializable @SerialName("repeated") data class Repeated(
    override val filename: String,
    override val scale: Float,
  ): BackgroundImageType()

  @Serializable @SerialName("static") data class Static(
    override val filename: String,
    override val scale: Float,
    val scaleType: BackgroundImageScaleType,
  ): BackgroundImageType()

  @Composable
  fun defaultBackgroundColor(theme: DefaultTheme): Color =
    if (this is Repeated) {
      PredefinedBackgroundImage.from(filename)!!.background[theme]!!
    } else {
      MaterialTheme.colors.background
    }

  @Composable
  fun defaultTintColor(theme: DefaultTheme): Color =
    if (this is Repeated) {
      PredefinedBackgroundImage.from(filename)!!.tint[theme]!!
    } else if (this is Static && scaleType == BackgroundImageScaleType.REPEAT) {
      MaterialTheme.colors.primary
    } else {
      MaterialTheme.colors.background.copy(0.9f)
    }

  companion object {
    val default: BackgroundImageType
      get() = PredefinedBackgroundImage.CAT.toType()

    private var cachedImage: Pair<String, ImageBitmap>? = null
  }
}

fun DrawScope.chatViewBackground(image: ImageBitmap, imageType: BackgroundImageType, background: Color, tint: Color) = clipRect {
  fun repeat(imageScale: Float) {
    val scale = imageScale * density
    for (h in 0..(size.height / image.height / scale).roundToInt()) {
      for (w in 0..(size.width / image.width / scale).roundToInt()) {
        drawImage(
          image,
          dstOffset = IntOffset(x = (w * image.width * scale).roundToInt(), y = (h * image.height * scale).roundToInt()),
          dstSize = IntSize((image.width * scale).roundToInt(), (image.height * scale).roundToInt()),
          colorFilter = ColorFilter.tint(tint, BlendMode.SrcIn)
        )
      }
    }
  }

  drawRect(background)
  when (imageType) {
    is BackgroundImageType.Repeated -> repeat(imageType.scale)
    is BackgroundImageType.Static -> when (imageType.scaleType) {
      BackgroundImageScaleType.REPEAT -> repeat(imageType.scale)
      BackgroundImageScaleType.FILL, BackgroundImageScaleType.FIT -> {
        val scale = imageType.scaleType.contentScale.computeScaleFactor(Size(image.width.toFloat(), image.height.toFloat()), Size(size.width, size.height))
        val scaledWidth = (image.width * scale.scaleX).roundToInt()
        val scaledHeight = (image.height * scale.scaleY).roundToInt()
        drawImage(image, dstOffset = IntOffset(x = ((size.width - scaledWidth) / 2).roundToInt(), y = ((size.height - scaledHeight) / 2).roundToInt()), dstSize = IntSize(scaledWidth, scaledHeight))
        if (imageType.scaleType == BackgroundImageScaleType.FIT) {
          if (scaledWidth < size.width) {
            // has black lines at left and right sides
            var x = (size.width - scaledWidth) / 2
            while (x > 0) {
              drawImage(image, dstOffset = IntOffset(x = (x - scaledWidth).roundToInt(), y = ((size.height - scaledHeight) / 2).roundToInt()), dstSize = IntSize(scaledWidth, scaledHeight))
              x -= scaledWidth
            }
            x = size.width - (size.width - scaledWidth) / 2
            while (x < size.width) {
              drawImage(image, dstOffset = IntOffset(x = x.roundToInt(), y = ((size.height - scaledHeight) / 2).roundToInt()), dstSize = IntSize(scaledWidth, scaledHeight))
              x += scaledWidth
            }
          } else {
            // has black lines at top and bottom sides
            var y = (size.height - scaledHeight) / 2
            while (y > 0) {
              drawImage(image, dstOffset = IntOffset(x = ((size.width - scaledWidth) / 2).roundToInt(), y = (y - scaledHeight).roundToInt()), dstSize = IntSize(scaledWidth, scaledHeight))
              y -= scaledHeight
            }
            y = size.height - (size.height - scaledHeight) / 2
            while (y < size.height) {
              drawImage(image, dstOffset = IntOffset(x = ((size.width - scaledWidth) / 2).roundToInt(), y = y.roundToInt()), dstSize = IntSize(scaledWidth, scaledHeight))
              y += scaledHeight
            }
          }
        }
        drawRect(tint)
      }
    }
  }
}

import chat.simplex.common.platform.*
import chat.simplex.common.showApp

fun main() {
  initHaskell()
  initApp()
  tmpDir.deleteRecursively()
  return showApp()
}

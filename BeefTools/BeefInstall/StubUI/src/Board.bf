using Beefy.widgets;
using Beefy.geom;
using Beefy.gfx;
using System.Diagnostics;
using System;
using System.IO;
using System.Threading;
using BiUtils;

namespace BIStubUI
{
	class BiButtonWidget : ButtonWidget
	{
		public Image mImage;
		public Image mImageHi;

		public override void Draw(Graphics g)
		{
			if (mMouseOver && mMouseDown)
				g.Draw(mImageHi);
			if (mMouseOver)
		    	g.Draw(mImageHi);
			else
				g.Draw(mImage);

			/*using (g.PushColor(0x8000FF00))
				g.FillRect(0, 0, mWidth, mHeight);*/
		}

		public override void DrawAll(Graphics g)
		{
			using (g.PushColor(mDisabled ? 0xD0A0A0A0 : 0xFFFFFFFF))
				base.DrawAll(g);
		}

		public override void MouseEnter()
		{
			base.MouseEnter();
			if (!mDisabled)
			{
				gApp.SetCursor(.Hand);
				gApp.mSoundManager.PlaySound(Sounds.sMouseOver);
			}
		}

		public override void MouseDown(float x, float y, int32 btn, int32 btnCount)
		{
			base.MouseDown(x, y, btn, btnCount);
			if (!mDisabled)
				gApp.mSoundManager.PlaySound(Sounds.sButtonPress);
		}

		public override void MouseLeave()
		{
			base.MouseLeave();
			gApp.SetCursor(.Pointer);
		}
	}

	class BiDialogButton : BiButtonWidget
	{
		public String mLabel ~ delete _;

		public override void Draw(Graphics g)
		{
			base.Draw(g);

			g.SetFont(gApp.mBtnFont);
			g.DrawString(mLabel, 0, 14, .Centered, mWidth);
		}
	}

	class BiCheckbox : CheckBox
	{
		public State mState;
		public String mLabel ~ delete _;

		public override bool Checked
		{
			get
			{
				return mState != .Unchecked;
			}

			set
			{
				gApp.mSoundManager.PlaySound(Sounds.sChecked);
				mState = value ? .Checked : .Unchecked;
			}
		}

		public override State State
		{
			get
			{
				return mState;
			}

			set
			{
				mState = value;
			}
		}

		public override void Draw(Graphics g)
		{
			if (mState == .Checked)
				g.Draw(Images.sChecked);
			else
				g.Draw(Images.sUnchecked);

			g.SetFont(gApp.mBodyFont);
			using (g.PushColor(0xFF000000))
				g.DrawString(mLabel, 40, 2);

			/*using (g.PushColor(0x20FF0000))
				g.FillRect(0, 0, mWidth, mHeight);*/
		}

		public override void MouseEnter()
		{
			base.MouseEnter();
			gApp.SetCursor(.Hand);
		}

		public override void MouseLeave()
		{
			base.MouseLeave();
			gApp.SetCursor(.Pointer);
		}
	}

	class BiInstallPathBox : Widget
	{
		public String mInstallPath = new .() ~ delete _;
		ImageWidget mBrowseButton;

		public this()
		{
			mBrowseButton = new ImageWidget();
			mBrowseButton.mImage = Images.sBrowse;
			mBrowseButton.mDownImage = Images.sBrowseDown;
			mBrowseButton.mOnMouseClick.Add(new (mouseArgs) =>
				{
					var folderDialog = scope FolderBrowserDialog();
					folderDialog.SelectedPath = mInstallPath;
					if (folderDialog.ShowDialog(mWidgetWindow).GetValueOrDefault() == .OK)
					{
						var selectedPath = scope String..AppendF(folderDialog.SelectedPath);
						mInstallPath.Set(selectedPath);
					}
				});
			AddWidget(mBrowseButton);
		}

		public void ResizeComponenets()
		{
			mBrowseButton.Resize(mWidth - 30, 2, Images.sBrowse.mWidth, Images.sBrowse.mHeight);
		}

		public override void Resize(float x, float y, float width, float height)
		{
			base.Resize(x, y, width, height);
			ResizeComponenets();
		}

		public override void Update()
		{
			base.Update();
			ResizeComponenets();
		}

		public override void Draw(Graphics g)
		{
			base.Draw(g);

			g.DrawButton(Images.sTextBox, 0, 0, mWidth);
			using (g.PushColor(0xFF000000))
			{
				g.SetFont(gApp.mBodyFont);
				g.DrawString("Installation path", 0, -32);
				g.SetFont(gApp.mBoxFont);
				g.DrawString(mInstallPath, 4, 0, .Left, mWidth - 36, .Ellipsis);
			}
		}
	}

	class Board : Widget
	{
		const float cBodyX = 0;
		const float cBodyY = 20;

		enum State
		{
			Options,
			Eula,
			Installing,
			Done
		}

		LabelWidget mHeaderLabel;
		BiButtonWidget mCloseButton;
		BiDialogButton mCancelButton;
		BiDialogButton mInstallButton;
		BiCheckbox mInstallForAllCheckbox;
		BiCheckbox mAddToPathCheckbox;
		BiCheckbox mAddToDesktopCheckbox;
		BiCheckbox mStartAfterCheckbox;
		BiInstallPathBox mInstallPathBox;
		EulaEditWidget mEulaEdit;

		Thread mInstallThread ~ delete _;

		float mScale = 0.35f;
		float mScaleVel = 0.2f;

		float mSurprisePct = 1.0f;
		float mHeadRaise = 1.0f;
		float mEatPct;
		bool mAcceptedEula;

		int mCloseTicks;
		int mInstallTicks;
		public bool mIsClosed;
		State mState;
		String mInstallPath ~ delete _;
		bool mWantsOptionsSetting;

		public float mPhysInstallPct;
		public float mInstallPct;

		public this()
		{
			mHeaderLabel = new LabelWidget();
			mHeaderLabel.mLabel = new String("Beef Development Tools");
			mHeaderLabel.mAlign = .Centered;
			mHeaderLabel.mColor = 0xFF000000;
			mHeaderLabel.mFont = gApp.mHeaderFont;
			mHeaderLabel.mMouseVisible = false;
			AddWidget(mHeaderLabel);

			mCloseButton = new BiButtonWidget();
			mCloseButton.mImage = Images.sClose;
			mCloseButton.mImageHi = Images.sCloseHi;
			mCloseButton.mOnMouseClick.Add(new (mouseArgs) =>
				{
					gApp.mCancelling = true;
				});
			mCloseButton.mMouseInsets = new Insets(4, 4, 4, 4);
			AddWidget(mCloseButton);

			BiCheckbox CreateCheckbox(StringView label, bool check = true)
			{
				var checkbox = new BiCheckbox();
				checkbox.mState = .Checked;
				checkbox.mLabel = new String(label);
				checkbox.mMouseInsets = new .(4, 0, 4, 0);
				AddWidget(checkbox);
				return checkbox;
			}

			mInstallForAllCheckbox = CreateCheckbox("Install for all users");
			mAddToPathCheckbox = CreateCheckbox("Add to path");
			mAddToDesktopCheckbox = CreateCheckbox("Add to desktop");
			mStartAfterCheckbox = CreateCheckbox("Run after install");

			mInstallPathBox = new BiInstallPathBox();
			AddWidget(mInstallPathBox);

			mEulaEdit = new EulaEditWidget();
			String eula = scope .();
			if (File.ReadAllText(scope String()..Concat(gApp.mInstallDir, "license.txt"), eula) case .Err)
				gApp.Fail("Failed to load license.txt");
			mEulaEdit.SetText(eula);
			AddWidget(mEulaEdit);

			mCancelButton = new BiDialogButton();
			mCancelButton.mLabel = new .("Cancel");
			mCancelButton.mImage = Images.sButton;
			mCancelButton.mImageHi = Images.sButtonHi;
			mCancelButton.mOnMouseClick.Add(new (mouseArgs) =>
				{
					gApp.mCancelling = true;
				});
			mCancelButton.mMouseInsets = new Insets(4, 4, 4, 4);
			AddWidget(mCancelButton);

			mInstallButton = new BiDialogButton();
			mInstallButton.mLabel = new .("Install");
			mInstallButton.mImage = Images.sButton;
			mInstallButton.mImageHi = Images.sButtonHi;
			mInstallButton.mOnMouseClick.Add(new (mouseArgs) =>
				{
					StartInstall();
				});
			mInstallButton.mMouseInsets = new Insets(4, 4, 4, 4);
			AddWidget(mInstallButton);

			////

			int pidl = 0;
			Windows.SHGetSpecialFolderLocation(gApp.mMainWindow.HWND, Windows.CSIDL_PROGRAM_FILES, ref pidl);
			if (pidl != 0)
			{
				char8* selectedPathCStr = scope char8[Windows.MAX_PATH]*;
				Windows.SHGetPathFromIDList(pidl, selectedPathCStr);
				mInstallPathBox.mInstallPath.Set(StringView(selectedPathCStr));
			}
			else
			{
				mInstallPathBox.mInstallPath.Set(@"C:\Program Files");
			}
			mInstallPathBox.mInstallPath.Append(@"\BeefLang");
		}

		Result<void> CreateDirectory(StringView dirPath)
		{
			for (int i < 10)
			{
				if (Directory.CreateDirectory(dirPath) case .Ok)
					return .Ok;
				Thread.Sleep(10);
			}
			return .Err;
		}

		void InstallProc()
		{
			bool needsElevation = false;
			bool allUsers = mInstallForAllCheckbox.Checked;
			bool addToPath = mAddToPathCheckbox.Checked;

			String pathPath = scope String()..Concat(mInstallPath, @"\bin");

			String programsPath = scope String();
			Platform.GetStrHelper(programsPath, scope (outPtr, outSize, outResult) =>
				{
					Platform.BfpDirectory_GetSysDirectory(allUsers ? .Programs_Common : .Programs, outPtr, outSize, (Platform.BfpFileResult*)outResult);
				});

			String beefProgramsPath = scope .();
			if (!programsPath.IsEmpty)
				beefProgramsPath.Concat(programsPath, @"\Beef Development Tools");

			if ((allUsers) && (addToPath))
			{
				if (BiUtils.Utils.ModifyPath(allUsers, pathPath, .Check) case .Err)
					needsElevation = true;
			}

			if (Directory.CreateDirectory(beefProgramsPath) case .Err)
				needsElevation = true;

			if (Directory.CreateDirectory(mInstallPath) case .Err)
				needsElevation = true;

			if (needsElevation)
			{
				String exeFilePath = scope .();
				Environment.GetExecutableFilePath(exeFilePath);

				String elevatePath = scope String();
				Path.GetDirectoryPath(exeFilePath, elevatePath);
				if (exeFilePath.EndsWith("_d.exe", .OrdinalIgnoreCase))
					elevatePath.AppendF(@"\BeefInstallElevated_d.exe");
				else
					elevatePath.AppendF(@"\BeefInstallElevated.exe");

				String args = scope String();
				args.AppendF("\"{}\" -path=\"{}\"", mInstallPath, pathPath);
				if (allUsers)
					args.Append(" -allUsers");
				if (addToPath)
					args.Append(" -addToPath");
				if (!beefProgramsPath.IsEmpty)
					args.AppendF(" -mkdir=\"{}\"", beefProgramsPath);

				ProcessStartInfo procInfo = scope ProcessStartInfo();
				procInfo.UseShellExecute = true;
				procInfo.SetFileName(elevatePath);
				procInfo.CreateNoWindow = true;
				procInfo.SetArguments(args);

				bool elevateFailed = false;

				SpawnedProcess process = scope SpawnedProcess();
				if (process.Start(procInfo) case .Err)
				{
					elevateFailed = true;
				}
				else
				{
					process.WaitFor();
					if (process.ExitCode != 0)
						elevateFailed = true;
				}

				if (elevateFailed)
				{
					mWantsOptionsSetting = true;
					if (Windows.MessageBoxA(mWidgetWindow.HWND, "Failed to install for all users. Change options to just install for the current user?", "ELEVATION FAILED",
						Windows.MB_ICONQUESTION | Windows.MB_YESNO) == Windows.IDYES)
					{
						mInstallForAllCheckbox.[Friend]mState = .Unchecked;

						mInstallPath.Clear();
						Platform.GetStrHelper(mInstallPath, scope (outPtr, outSize, outResult) =>
							{
								Platform.BfpDirectory_GetSysDirectory(.AppData_Local, outPtr, outSize, (Platform.BfpFileResult*)outResult);
							});
						mInstallPath.Append(@"\BeefLang");
					}
					return;
				}
			}

			Thread rehupThread = scope Thread(new => Utils.RehupEnvironment);
			rehupThread.Start(false);

			Utils.RemovedInstalledFiles(mInstallPath, false);

			int handledSize = 0;
			int totalSize = 0;
			for (let entry in gApp.mFileList)
			{
				totalSize += entry.mSize;
			}

			InstalledFiles installedFiles = scope .();

			for (let entry in gApp.mFileList)
			{
				if (gApp.WantsShutdown)
					break;

				String destPath = scope String();

				destPath.Append(mInstallPath);
				destPath.Append("\\");
				destPath.Append(entry.mPath);

				String destDir = scope String();
				Path.GetDirectoryPath(destPath, destDir);
				if (Directory.CreateDirectory(destDir) case .Err)
				{
					gApp.Fail(scope String()..AppendF("Failed to create directory '{}'", destDir));
					return;
				}

				gApp.mExtractFunc(entry.mId, destPath);

				handledSize += entry.mSize;
				if (totalSize > 0)
					mPhysInstallPct = (float)handledSize / totalSize;

				installedFiles.Add(entry.mPath);
			}

			if (!gApp.WantsShutdown)
			{
				if (Directory.CreateDirectory(beefProgramsPath) case .Err)
				{
					gApp.Fail(scope String()..AppendF("Failed to create directory '{}'", beefProgramsPath));
				}

				void CreateShortcut(StringView linkPath, StringView targetPath, StringView arguments, StringView workingDirectory, StringView description)
				{
					if (Shell.CreateShortcut(linkPath, targetPath, arguments, workingDirectory, description) case .Err)
					{
						gApp.Fail(scope String()..AppendF("Failed to create shortcut '{}'", linkPath));
					}
					else
						installedFiles.Add(linkPath);
				}
				
				CreateShortcut(scope String()..Concat(beefProgramsPath, @"\Beef IDE.lnk"), scope String()..Concat(mInstallPath, @"\bin\BeefIDE.exe"), "", mInstallPath, "Beef IDE");
				CreateShortcut(scope String()..Concat(beefProgramsPath, @"\Beef IDE (Debug).lnk"), scope String()..Concat(mInstallPath, @"\bin\BeefIDE (Debug).exe"), "", mInstallPath, "Beef IDE (Debug)");
				CreateShortcut(scope String()..Concat(beefProgramsPath, @"\Documentation.lnk"), "http://beeflang.org/docs/", "", mInstallPath, "Beef IDE (Debug)");
				CreateShortcut(scope String()..Concat(beefProgramsPath, @"\LICENSE.lnk"), scope String()..Concat(mInstallPath, @"\LICENSE.TXT"), "", mInstallPath, "Beef License");
				CreateShortcut(scope String()..Concat(beefProgramsPath, @"\README.lnk"), scope String()..Concat(mInstallPath, @"\bin\readme.txt"), "", mInstallPath, "Beef ReadMe");
				installedFiles.Add(scope String()..Concat(beefProgramsPath, @"\"));
			}

			installedFiles.Serialize(scope String()..Concat(mInstallPath, @"\install.lst")).IgnoreError();

			if (gApp.WantsShutdown)
			{
				if (addToPath)
				{
					rehupThread.Join();

					Utils.ModifyPath(allUsers, pathPath, .Remove).IgnoreError();

					// Rehup AGAIN...
					rehupThread = scope:: Thread(new => Utils.RehupEnvironment);
					rehupThread.Start(false);
				}

				Utils.CleanupDir(mInstallPath);
				Utils.CleanupDir(beefProgramsPath);
			}

			rehupThread.Join();
		}

		void StartInstall()
		{
			if (mState == .Done)
			{
				gApp.mClosing = true;
				return;
			}

			if ((mState == .Options) && (!mAcceptedEula))
			{
				mState = .Eula;
				return;
			}

			if (mState == .Eula)
			{
				mAcceptedEula = true;
			}

			if (mInstallPath == null)
				mInstallPath = new String();
			mInstallPath.Set(mInstallPathBox.mInstallPath);

			mState = .Installing;
			mInstallButton.mDisabled = true;
			mInstallButton.mMouseVisible = false;
			mInstallPathBox.mVisible = false;

			mInstallThread = new Thread(new => InstallProc);
			mInstallThread.Start(false);
		}

		public override void Draw(Graphics g)
		{
			float bodyX = cBodyX;
			float bodyY = cBodyY;

			g.Draw(Images.sBody, bodyX, bodyY);

			float headRaise = mHeadRaise;
			headRaise += Math.Sin(Math.Clamp((mEatPct - 0.2f) * 1.4f, 0, 1.0f) * Math.PI_f*6) * 0.02f;
			
			float headX = bodyX + 664 - headRaise * 6;
			float headY = bodyY + 192 - headRaise * 30;

			headY += Math.Clamp(Math.Sin(Math.PI_f * mEatPct) * 3.0f, 0, 1) * 8.0f;

			Images.sHead.mPixelSnapping = .Never;
			Images.sEyesOpen.mPixelSnapping = .Never;
			Images.sEyesClosed.mPixelSnapping = .Never;
			g.Draw(Images.sHead, headX, headY);
			g.Draw((mSurprisePct > 0) ? Images.sEyesOpen : Images.sEyesClosed, headX + 70, headY + 190);

			if (mState == .Installing)
			{
				float totalWidth = 410;
				float fillWidth = totalWidth * (mInstallPct*0.9f + 0.1f);
				if (gApp.mClosing)
					fillWidth = totalWidth * mInstallPct;

				float barX = 200;
				float barY = 240;

				float barHeight = Images.sPBBarBottom.mHeight;
				using (g.PushClip(barX, barY, totalWidth, barHeight))
				{
					g.DrawButton(Images.sPBBarBottom, barX, barY, totalWidth);

					Color colorLeft = 0x800288E9;
					Color colorRight = 0x80FFFFFF;
					if (gApp.mClosing)
					{
						colorLeft = 0x80000000;
						colorRight = 0x800288E9;
					}
					g.FillRectGradient(barX, barY, fillWidth, barHeight, colorLeft, colorRight, colorLeft, colorRight);

					float barPct = (mInstallTicks % 60) / 60.0f;
					for (int i = 0; i < 16; i++)
					{
						Images.sPBBarHilite.mPixelSnapping = .Never;
						using (g.PushColor(0x22FFFFFF))
							g.Draw(Images.sPBBarHilite, barX - 16 - totalWidth + fillWidth + (i + barPct) * 26, barY + 6);
					}

					g.DrawButton(Images.sPBBarEmpty, barX + fillWidth - 30, barY + 5, totalWidth - fillWidth + 40);

					g.DrawButton(Images.sPBFrameTop, barX, barY, totalWidth);

					g.DrawButton(Images.sPBFrameGlow, barX, barY, fillWidth);
				}

				g.SetFont(gApp.mBtnFont);
				using (g.PushColor(0xFF000000))
					g.DrawString(gApp.mClosing ? "Cancelling ..." : "Installing ...", 400, 190, .Centered);
			}

			if (mState == .Done)
			{
				g.Draw(Images.sSuccess, 120, 200);

				g.SetFont(gApp.mBtnFont);

				using (g.PushColor(0xFF008000))
					g.DrawString("Installation Completed", 250, 228);
			}
		}

		public override void MouseMove(float x, float y)
		{
			if (Rect(60, 24, 700, 420).Contains(x, y))
			{
				gApp.SetCursor(.SizeNESW);
			}
			else
			{
				gApp.SetCursor(.Pointer);
			}

			base.MouseMove(x, y);
		}

		public override void DrawAll(Graphics g)
		{
			int cBodyX = 0;
			int cBodyY = 0;

			/*using (g.PushColor(0x80FF0000))
				g.FillRect(0, 0, mWidth, mHeight);*/

			//float scaleX = (Math.Cos(mUpdateCnt * 0.1f) + 1.0f) * 0.5f;
			//float scaleY = scaleX;
			float scaleX = mScale;
			float scaleY = mScale;

			if ((Math.Abs(scaleX - 1.0f) < 0.001) && (Math.Abs(scaleY - 1.0f) < 0.001))
				base.DrawAll(g);
			else using (g.PushScale(scaleX, scaleY, cBodyX + 400, cBodyY + 560))
				base.DrawAll(g);
		}

		public bool IsDecompressing
		{
			get
			{
				//return gApp.
				return false;
			}
		}

		public override void Update()
		{
			base.Update();

			ResizeComponents();

			if ((mState == .Installing) && (!gApp.mClosing))
				mInstallPct = mInstallPct + (mPhysInstallPct - mInstallPct) * 0.1f;

			if (mInstallThread != null)
			{
				if (mInstallThread.Join(0))
				{
					DeleteAndNullify!(mInstallThread);
					if (mWantsOptionsSetting)
					{
						mInstallPathBox.mInstallPath.Set(mInstallPath);
						mWantsOptionsSetting = false;
						mState = .Options;
						mInstallButton.mDisabled = false;
						mInstallButton.mMouseVisible = true;
					}
				}
			}

			if (gApp.mClosing)
			{
				if (mState == .Installing)
				{
					mCancelButton.mDisabled = true;
					mCancelButton.mMouseVisible = false;
				}

				if (mState == .Installing)
				{
					mInstallTicks--;
					if (mInstallTicks < 0)
						mInstallTicks = 0x3FFFFFFF;
				}

				if ((mState == .Installing) && (mInstallPct > 0))
				{
					mInstallPct = (mInstallPct * 0.985f) - 0.002f;
					if (mInstallThread != null)
						mInstallPct = Math.Max(mInstallPct, 0.1f);
					return;
				}

				if ((mInstallThread != null) && (mInstallPct >= 0.01f))
				{
					return;
				}

				if (mCloseTicks == 0)
				{
					gApp.mSoundManager.PlaySound(Sounds.sAbort);
					mScaleVel = 0.055f;
				}
				mCloseTicks++;

				mScaleVel *= 0.90f;
				mScaleVel -= 0.01f;
				mScale += mScaleVel;
				if (mState != .Done)
				{
					mSurprisePct = 1.0f;
					mHeadRaise = Math.Clamp(mHeadRaise + 0.2f, 0, 1.0f);
				}

				if (mScale <= 0)
				{
					mScale = 0.0f;
				}

				if (mCloseTicks == 60)
					mIsClosed = true;

				return;
			}

			if (mState == .Installing)
			{
				mInstallTicks++;

				if (mInstallThread == null)
				{
					mState = .Done;
					mInstallButton.mDisabled = false;
					mInstallButton.mMouseVisible = true;
				}
			}

			if (mUpdateCnt == 1)
				gApp.mSoundManager.PlaySound(Sounds.sBoing);

			float sizeTarget = Math.Min(0.5f + mUpdateCnt * 0.05f, 1.0f);

			float scaleDiff = sizeTarget - mScale;
			mScaleVel += scaleDiff * 0.05f;
			mScaleVel *= 0.80f;
			mScale += mScaleVel;

			mSurprisePct = Math.Max(mSurprisePct - 0.005f, 0);
			if (mUpdateCnt > 240)
			{
				mHeadRaise = Math.Max(mHeadRaise * 0.95f - 0.01f, 0);
			}

			if (mEatPct == 0.0f)
			{
				if ((mUpdateCnt == 600) || (mUpdateCnt % 2400 == 0))
				{
					mEatPct = 0.0001f;
				}
			}
			else
			{
				let prev = mEatPct;
				mEatPct += 0.004f;
				if ((prev < 0.2f) && (mEatPct >= 0.2f))
					gApp.mSoundManager.PlaySound(Sounds.sEating);

				if (mEatPct >= 1.0f)
				{
					//Debug.WriteLine("Eat done");
					mEatPct = 0;
				}
			}

			if (mUpdateCnt % 2200 == 0)
			{
				mSurprisePct = 0.5f;
			}

			if (mState == .Options)
				mInstallButton.mLabel.Set("Install");
			else if (mState == .Eula)
				mInstallButton.mLabel.Set("I Accept");
			else if (mState == .Installing)
				mInstallButton.mLabel.Set("Wait...");
			else if (mState == .Done)
				mInstallButton.mLabel.Set("Finish");
		}

		public override void UpdateAll()
		{
			base.UpdateAll();

			if (mWidgetWindow.IsKeyDown(.Control))
			{
				for (int i < 2)
					base.UpdateAll();
			}
		}

		public override void MouseDown(float x, float y, int32 btn, int32 btnCount)
		{
			base.MouseDown(x, y, btn, btnCount);
		}

		public override void KeyDown(KeyCode keyCode, bool isRepeat)
		{
			base.KeyDown(keyCode, isRepeat);

			if (keyCode == .Space)
			{
				gApp.mWantRehup = true;
			}
		}

		void UpdateComponent(Widget widget, int updateOffset, float centerX = 0.5f, float centerY = 0.5f, float speedMult = 1.0f)
		{
			float pct = Math.Clamp((mUpdateCnt - 50 - updateOffset) * 0.25f * speedMult, 0, 1.0f);
			//float pct = Math.Clamp((mUpdateCnt - 50 - updateOffset) * 0.02f, 0, 1.0f);
			if (pct == 0)
			{
				widget.SetVisible(false);
				return;
			}
			widget.SetVisible(true);
			if (pct == 1)
			{
				widget.ClearTransform();
				return;
			}
			
			Matrix matrix = .IdentityMatrix;
			matrix.Translate(-widget.mWidth * centerX, -widget.mHeight * centerY);
			matrix.Scale(pct, pct);
			matrix.Translate(widget.mWidth * centerX, widget.mHeight * centerY);
			matrix.Translate(widget.mX, widget.mY);
			widget.Transform = matrix;
		}

		void ResizeComponents()
		{
			float headerWidth = mHeaderLabel.CalcWidth();
			mHeaderLabel.Resize(cBodyX + 375 - headerWidth/2, cBodyY + 60, headerWidth, 60);
			UpdateComponent(mHeaderLabel, 0, 0.5f, 2.0f, 0.4f);

			mCloseButton.Resize(cBodyX + 660, cBodyY + 55, mCloseButton.mImage.mWidth, mCloseButton.mImage.mHeight);
			UpdateComponent(mCloseButton, 5);

			mInstallForAllCheckbox.Resize(cBodyX + 120, cBodyY + 136, 30, 40);
			UpdateComponent(mInstallForAllCheckbox, 10);

			mAddToPathCheckbox.Resize(cBodyX + 418, cBodyY + 136, 30, 40);
			UpdateComponent(mAddToPathCheckbox, 12);

			mAddToDesktopCheckbox.Resize(cBodyX + 120, cBodyY + 190, 30, 40);
			UpdateComponent(mAddToDesktopCheckbox, 14);

			mStartAfterCheckbox.Resize(cBodyX + 418, cBodyY + 190, 30, 40);
			UpdateComponent(mStartAfterCheckbox, 16);

			if (mState == .Options)
			{
				mInstallPathBox.Resize(cBodyX + 122, cBodyY + 276, 508, Images.sTextBox.mHeight);
				UpdateComponent(mInstallPathBox, 5, 0.1f, 0.5f, 0.4f);
			}

			if (mState == .Eula)
			{
				mEulaEdit.SetVisible(true);
				mEulaEdit.Resize(cBodyX + 165, cBodyY + 120, 480, 190);
			}
			else
				mEulaEdit.SetVisible(false);

			if (mState != .Options)
			{
				mInstallForAllCheckbox.SetVisible(false);
				mAddToPathCheckbox.SetVisible(false);
				mAddToDesktopCheckbox.SetVisible(false);
				mStartAfterCheckbox.SetVisible(false);
				mInstallPathBox.SetVisible(false);
			}

			mCancelButton.Resize(cBodyX + 180, cBodyY + 320, mCancelButton.mImage.mWidth, mCancelButton.mImage.mHeight);
			UpdateComponent(mCancelButton, 13, 0.5f, 0.2f);

			mInstallButton.Resize(cBodyX + 404, cBodyY + 320, mInstallButton.mImage.mWidth, mInstallButton.mImage.mHeight);
			UpdateComponent(mInstallButton, 15, 0.5f, 0.2f);
		}

		public override void Resize(float x, float y, float width, float height)
		{
			base.Resize(x, y, width, height);
			ResizeComponents();
		}
	}
}